# Windows Top-Right Auto Hide Design

## Goal

On Windows, Lockly opens pinned to the top-right corner of the current monitor work area and behaves like a QQ-style edge panel: after the mouse leaves a right-docked window, the app slides mostly off the right edge and can be revealed by moving the mouse back to the right-edge hot zone. The native Windows title bar is removed, and Lockly provides compact in-page minimize and exit controls.

## Scope

- Windows only.
- No Flutter plugin dependency is added.
- Android files and behavior remain unchanged.
- The feature lives in the native Windows runner because the hidden window must still react to global cursor position while mostly off-screen.
- The in-page controls use a native `lockly/window` method channel instead of adding a window-management plugin.

## Behavior

- The Windows runner uses a frameless `WS_POPUP | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU` window style instead of `WS_OVERLAPPEDWINDOW`.
- The default Windows window size is reduced from `430x860` to `392x784`.
- Flutter adds a 34 px Windows-only chrome area with in-page minimize and exit buttons at the top right. Non-Windows platforms do not render this chrome.
- The top chrome area outside the button strip returns `HTCAPTION` from `WM_NCHITTEST` so the frameless window can still be dragged.
- Before the window is shown, `Win32Window::Show()` aligns it to `monitor_info.rcWork.right - window_width` and `monitor_info.rcWork.top`.
- A Win32 timer polls cursor position every 50 ms.
- When the cursor remains outside a right-docked visible window for 700 ms, the window slides over 180 ms to `monitor_info.rcWork.right - 6`, leaving only a small right-edge grip.
- While hidden, moving the cursor into the right-edge reveal hot zone, 18 px wide and as tall as the docked window, slides the window back into view.
- When the user finishes dragging the window near the right edge, the runner snaps it back to the right edge and keeps the current vertical position clamped inside the monitor work area.
- If the user finishes dragging the window away from the right edge, the runner clears the right-docked state and does not auto-hide until the window is docked again.
- The code uses `MonitorFromWindow` and `MONITORINFO.rcWork` so the work area respects taskbars and multi-monitor layouts.

## Verification

- `test/windows_configuration_test.dart` statically verifies that the Windows runner contains frameless chrome, top-right alignment, right-edge hide/reveal, slide animation, post-drag right-edge docking, timer cleanup, native minimize/close method handling, and does not introduce `window_manager`.
- `test/ui/windows_window_controls_test.dart` verifies that Windows renders in-page minimize/exit controls and non-Windows platforms do not.
- `flutter test test\windows_configuration_test.dart test\ui\windows_window_controls_test.dart -r compact --concurrency=1` passes with `NO_PROXY=localhost,127.0.0.1,::1`.
- `flutter build windows --release` passes and produces `build\windows\x64\runner\Release\Lockly.exe`.
