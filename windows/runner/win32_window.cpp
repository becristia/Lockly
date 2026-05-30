#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

constexpr UINT_PTR kTopRightAutoHideTimerId = 0x4c01;
constexpr UINT kAutoHidePollMs = 250;
constexpr ULONGLONG kAutoHideDelayMs = 700;
constexpr ULONGLONG kSlideAnimationMs = 180;
constexpr int kHiddenGripWidth = 6;
constexpr int kRevealHotZoneWidth = 18;
constexpr int kRightDockSnapThreshold = 96;
constexpr int kDragHandleHeight = 34;
constexpr int kChromeButtonStripWidth = 96;

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  constexpr DWORD kFramelessWindowStyle =
      WS_POPUP | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
  HWND window = CreateWindow(
      window_class, title.c_str(), kFramelessWindowStyle,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  AlignToTopRightWorkArea();
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCHITTEST: {
      const LRESULT hit = DefWindowProc(hwnd, message, wparam, lparam);
      if (hit != HTCLIENT) {
        return hit;
      }

      RECT window_rect;
      if (!GetWindowRect(hwnd, &window_rect)) {
        return hit;
      }

      const POINT cursor = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const bool is_drag_zone =
          cursor.y >= window_rect.top &&
          cursor.y < window_rect.top + kDragHandleHeight &&
          cursor.x >= window_rect.left &&
          cursor.x < window_rect.right - kChromeButtonStripWidth;
      return is_drag_zone ? HTCAPTION : hit;
    }

    case WM_TIMER:
      if (wparam == kTopRightAutoHideTimerId) {
        ApplyEdgeSlideAnimation();
        HandleTopRightAutoHideTimer();
        return 0;
      }
      break;

    case WM_EXITSIZEMOVE:
      HandleTopRightDockAfterMove();
      return 0;

    case WM_DESTROY:
      StopTopRightAutoHideTimer();
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  StopTopRightAutoHideTimer();
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::SetTopRightAutoHideEnabled(bool enabled) {
  top_right_auto_hide_enabled_ = enabled;
  if (enabled) {
    StartTopRightAutoHideTimer();
  } else {
    StopTopRightAutoHideTimer();
  }
}

void Win32Window::AlignToTopRightWorkArea() {
  if (!window_handle_) {
    return;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return;
  }

  MONITORINFO monitor_info;
  if (!GetCurrentMonitorInfo(&monitor_info)) {
    return;
  }

  const int window_width = window_rect.right - window_rect.left;
  const int x = monitor_info.rcWork.right - window_width;
  const int y = monitor_info.rcWork.top;
  SetWindowPos(window_handle_, nullptr, x, y, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  is_auto_hidden_ = false;
  is_right_docked_ = true;
  is_sliding_ = false;
  slide_target_hidden_ = false;
  dock_top_ = y;
  cursor_left_window_at_ = 0;
}

void Win32Window::StartTopRightAutoHideTimer() {
  if (!window_handle_ || !top_right_auto_hide_enabled_) {
    return;
  }

  SetTimer(window_handle_, kTopRightAutoHideTimerId, kAutoHidePollMs, nullptr);
}

void Win32Window::StopTopRightAutoHideTimer() {
  if (window_handle_) {
    KillTimer(window_handle_, kTopRightAutoHideTimerId);
  }
}

void Win32Window::HandleTopRightAutoHideTimer() {
  if (!window_handle_ || IsIconic(window_handle_) || is_sliding_) {
    return;
  }

  POINT cursor;
  if (!GetCursorPos(&cursor)) {
    return;
  }

  if (is_auto_hidden_) {
    if (IsCursorInRevealHotZone(cursor)) {
      RevealFromRightEdge();
    }
    return;
  }

  if (!is_right_docked_) {
    return;
  }

  if (IsCursorInsideWindow(cursor)) {
    cursor_left_window_at_ = 0;
    return;
  }

  const ULONGLONG now = GetTickCount64();
  if (cursor_left_window_at_ == 0) {
    cursor_left_window_at_ = now;
    return;
  }

  if (now - cursor_left_window_at_ >= kAutoHideDelayMs) {
    HideToRightEdge();
  }
}

void Win32Window::HandleTopRightDockAfterMove() {
  if (!window_handle_) {
    return;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return;
  }

  MONITORINFO monitor_info;
  if (!GetCurrentMonitorInfo(&monitor_info)) {
    return;
  }

  const int distance_to_right =
      monitor_info.rcWork.right > window_rect.right
          ? monitor_info.rcWork.right - window_rect.right
          : window_rect.right - monitor_info.rcWork.right;
  if (distance_to_right > kRightDockSnapThreshold) {
    is_auto_hidden_ = false;
    is_right_docked_ = false;
    is_sliding_ = false;
    slide_target_hidden_ = false;
    cursor_left_window_at_ = 0;
    return;
  }

  dock_top_ = ClampedDockTop(window_rect, monitor_info);
  SetWindowPos(window_handle_, nullptr, DockedRightX(window_rect, monitor_info),
               dock_top_, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  is_auto_hidden_ = false;
  is_right_docked_ = true;
  is_sliding_ = false;
  slide_target_hidden_ = false;
  cursor_left_window_at_ = 0;
}

void Win32Window::HideToRightEdge() {
  if (!window_handle_) {
    return;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return;
  }

  MONITORINFO monitor_info;
  if (!GetCurrentMonitorInfo(&monitor_info)) {
    return;
  }

  dock_top_ = ClampedDockTop(window_rect, monitor_info);
  StartEdgeSlideAnimation(HiddenRightX(monitor_info), true);
  cursor_left_window_at_ = 0;
}

void Win32Window::RevealFromRightEdge() {
  if (!window_handle_) {
    return;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return;
  }

  MONITORINFO monitor_info;
  if (!GetCurrentMonitorInfo(&monitor_info)) {
    return;
  }

  dock_top_ = ClampedDockTop(window_rect, monitor_info);
  StartEdgeSlideAnimation(DockedRightX(window_rect, monitor_info), false);
  cursor_left_window_at_ = 0;
}

void Win32Window::StartEdgeSlideAnimation(int target_x, bool target_hidden) {
  if (!window_handle_) {
    return;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return;
  }

  slide_start_x_ = window_rect.left;
  slide_target_x_ = target_x;
  slide_target_hidden_ = target_hidden;
  slide_started_at_ = GetTickCount64();
  is_sliding_ = true;
  SetTimer(window_handle_, kTopRightAutoHideTimerId, kAutoHidePollMs, nullptr);
}

void Win32Window::ApplyEdgeSlideAnimation() {
  if (!window_handle_ || !is_sliding_) {
    return;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    is_sliding_ = false;
    return;
  }

  const ULONGLONG elapsed = GetTickCount64() - slide_started_at_;
  int next_x = slide_target_x_;
  if (elapsed < kSlideAnimationMs) {
    next_x = slide_start_x_ +
             static_cast<int>((slide_target_x_ - slide_start_x_) *
                              static_cast<LONGLONG>(elapsed) /
                              static_cast<LONGLONG>(kSlideAnimationMs));
  }

  HWND z_order = slide_target_hidden_ ? nullptr : HWND_TOP;
  UINT flags = SWP_NOSIZE | SWP_NOACTIVATE;
  if (slide_target_hidden_) {
    flags |= SWP_NOZORDER;
  }
  SetWindowPos(window_handle_, z_order, next_x, dock_top_, 0, 0, flags);

  if (elapsed >= kSlideAnimationMs) {
    is_sliding_ = false;
    is_auto_hidden_ = slide_target_hidden_;
    is_right_docked_ = true;
    cursor_left_window_at_ = 0;
  }
}

int Win32Window::DockedRightX(const RECT& window_rect,
                              const MONITORINFO& monitor_info) const {
  const int window_width = window_rect.right - window_rect.left;
  return monitor_info.rcWork.right - window_width;
}

int Win32Window::HiddenRightX(const MONITORINFO& monitor_info) const {
  return monitor_info.rcWork.right - kHiddenGripWidth;
}

int Win32Window::ClampedDockTop(const RECT& window_rect,
                                const MONITORINFO& monitor_info) const {
  const int window_height = window_rect.bottom - window_rect.top;
  const int lowest_top =
      monitor_info.rcWork.bottom - window_height > monitor_info.rcWork.top
          ? monitor_info.rcWork.bottom - window_height
          : monitor_info.rcWork.top;
  if (window_rect.top < monitor_info.rcWork.top) {
    return monitor_info.rcWork.top;
  }
  if (window_rect.top > lowest_top) {
    return lowest_top;
  }
  return window_rect.top;
}

bool Win32Window::GetCurrentMonitorInfo(MONITORINFO* monitor_info) const {
  if (!window_handle_ || monitor_info == nullptr) {
    return false;
  }

  monitor_info->cbSize = sizeof(MONITORINFO);
  HMONITOR monitor = MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
  return monitor != nullptr && GetMonitorInfo(monitor, monitor_info);
}

bool Win32Window::IsCursorInsideWindow(const POINT& cursor) const {
  if (!window_handle_) {
    return false;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return false;
  }

  return cursor.x >= window_rect.left && cursor.x < window_rect.right &&
         cursor.y >= window_rect.top && cursor.y < window_rect.bottom;
}

bool Win32Window::IsCursorInRevealHotZone(const POINT& cursor) const {
  if (!window_handle_) {
    return false;
  }

  RECT window_rect;
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return false;
  }

  MONITORINFO monitor_info;
  if (!GetCurrentMonitorInfo(&monitor_info)) {
    return false;
  }

  const int window_height = window_rect.bottom - window_rect.top;
  const int reveal_bottom =
      dock_top_ + window_height < monitor_info.rcWork.bottom
          ? dock_top_ + window_height
          : monitor_info.rcWork.bottom;
  return cursor.x >= monitor_info.rcWork.right - kRevealHotZoneWidth &&
         cursor.x < monitor_info.rcWork.right &&
         cursor.y >= dock_top_ && cursor.y < reveal_bottom;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
