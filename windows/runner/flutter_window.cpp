#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayMenuRestore = 1001;
constexpr UINT kTrayMenuExit = 1002;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterWindowMethodChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();

  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_SIZE && wparam == SIZE_MINIMIZED) {
    if (flutter_controller_) {
      flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                    lparam);
    }
    AddTrayIcon(hwnd);
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  if (message == kTrayIconMessage) {
    const auto tray_event = LOWORD(lparam);
    if (tray_event == WM_LBUTTONUP || tray_event == WM_LBUTTONDBLCLK) {
      RestoreFromTray(hwnd);
    } else if (tray_event == WM_RBUTTONUP || tray_event == WM_CONTEXTMENU) {
      ShowTrayMenu(hwnd);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AddTrayIcon(HWND window) {
  if (tray_icon_added_) {
    return;
  }

  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_data_.hWnd = window;
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip, L"Lockly - Minimize to tray");

  tray_icon_added_ = Shell_NotifyIcon(NIM_ADD, &tray_icon_data_) == TRUE;
  if (tray_icon_added_) {
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIcon(NIM_SETVERSION, &tray_icon_data_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }

  Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void FlutterWindow::RestoreFromTray(HWND window) {
  RemoveTrayIcon();
  ShowWindow(window, SW_RESTORE);
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
  SetFocus(window);
}

void FlutterWindow::ShowTrayMenu(HWND window) {
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }

  AppendMenuW(menu, MF_STRING, kTrayMenuRestore, L"Restore");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"Exit");

  POINT cursor;
  GetCursorPos(&cursor);
  SetForegroundWindow(window);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, window, nullptr);
  DestroyMenu(menu);
  PostMessage(window, WM_NULL, 0, 0);

  if (command == kTrayMenuRestore) {
    RestoreFromTray(window);
  } else if (command == kTrayMenuExit) {
    RemoveTrayIcon();
    PostMessage(window, WM_CLOSE, 0, 0);
  }
}

void FlutterWindow::RegisterWindowMethodChannel() {
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "lockly/window",
          &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HWND window = GetHandle();
        if (!window) {
          result->Error("window_unavailable", "Window handle is unavailable");
          return;
        }

        if (call.method_name() == "minimize") {
          ShowWindow(window, SW_MINIMIZE);
          result->Success();
          return;
        }

        if (call.method_name() == "close") {
          PostMessage(window, WM_CLOSE, 0, 0);
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}
