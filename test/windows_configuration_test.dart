import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows configuration', () {
    test('runner and installer agree on the Lockly executable name', () {
      final cmake = File('windows/CMakeLists.txt').readAsStringSync();
      final runnerResources = File(
        'windows/runner/Runner.rc',
      ).readAsStringSync();
      final installer = File('windows/installer/lockly.iss').readAsStringSync();

      expect(cmake, contains('set(BINARY_NAME "Lockly")'));
      expect(
        runnerResources,
        contains('VALUE "OriginalFilename", "Lockly.exe"'),
      );
      expect(installer, contains('#define MyAppExeName "Lockly.exe"'));
    });

    test('installer targets per-user Windows install without elevation', () {
      final installer = File('windows/installer/lockly.iss').readAsStringSync();

      expect(
        installer,
        contains('DefaultDirName={localappdata}\\Programs\\{#MyAppName}'),
      );
      expect(installer, contains('PrivilegesRequired=lowest'));
      expect(installer, contains('ArchitecturesAllowed=x64compatible'));
      expect(
        installer,
        contains('ArchitecturesInstallIn64BitMode=x64compatible'),
      );
      expect(installer, contains('Source: "{#MyAppSourceDir}\\*"'));
      expect(
        installer,
        contains('Flags: ignoreversion recursesubdirs createallsubdirs'),
      );
    });

    test('Windows plugins include secure storage and local auth only', () {
      final plugins = File(
        'windows/flutter/generated_plugins.cmake',
      ).readAsStringSync();

      expect(plugins, contains('flutter_secure_storage_windows'));
      expect(plugins, contains('local_auth_windows'));
      expect(plugins, isNot(contains('android')));
    });

    test(
      'Windows FFI plugins are explicit and do not include Android-only scanners',
      () {
        final plugins = File(
          'windows/flutter/generated_plugins.cmake',
        ).readAsStringSync();
        final ffiListMatch = RegExp(
          r'list\(APPEND FLUTTER_FFI_PLUGIN_LIST\s+([\s\S]*?)\)',
        ).firstMatch(plugins);

        expect(ffiListMatch, isNotNull);
        final ffiPlugins = ffiListMatch!
            .group(1)!
            .split(RegExp(r'\s+'))
            .where((entry) => entry.isNotEmpty)
            .toList();

        expect(ffiPlugins, equals(['jni']));
        expect(ffiPlugins, isNot(contains('mobile_scanner')));
        expect(ffiPlugins, isNot(contains('local_auth_android')));
      },
    );

    test('installer smoke script uses a local disposable install target', () {
      final smokeScript = File(
        'windows/installer/install_smoke.ps1',
      ).readAsStringSync();

      expect(smokeScript, contains('ISCC.exe'));
      expect(smokeScript, contains('LocklyInstallerSetup.exe'));
      expect(smokeScript, contains('/VERYSILENT'));
      expect(smokeScript, contains('/SUPPRESSMSGBOXES'));
      expect(smokeScript, contains('/NORESTART'));
      expect(smokeScript, contains('/CURRENTUSER'));
      expect(smokeScript, contains('/NOICONS'));
      expect(smokeScript, contains('/DIR='));
      expect(smokeScript, contains('build\\windows\\install-smoke'));
      expect(smokeScript, contains('Unins*.exe'));
      expect(
        smokeScript,
        matches(
          RegExp(
            r'\$installRoot\s*=\s*Join-Path\s+\$projectRoot\s+"build\\windows\\install-smoke"',
          ),
        ),
      );
      expect(
        smokeScript,
        matches(
          RegExp(r'\$installDir\s*=\s*Join-Path\s+\$installRoot\s+"Lockly"'),
        ),
      );
      final removeItemLines = smokeScript
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.startsWith('Remove-Item '))
          .toList();
      expect(
        removeItemLines,
        everyElement(
          equals('Remove-Item -LiteralPath \$installRoot -Recurse -Force'),
        ),
      );
      expect(removeItemLines, hasLength(2));
      expect(
        RegExp(
          r'Assert-UnderProject\s+\$installRoot\s+Remove-Item\s+-LiteralPath\s+\$installRoot\s+-Recurse\s+-Force',
          multiLine: true,
        ).allMatches(smokeScript).length,
        equals(removeItemLines.length),
      );
      expect(
        smokeScript,
        matches(
          RegExp(
            r'Assert-UnderProject\s+\$installerOutputDir[\s\S]*?Assert-UnderProject\s+\$installRoot[\s\S]*?Assert-UnderProject\s+\$installDir',
          ),
        ),
      );
      expect(smokeScript, contains(r'"/DIR=$installDir"'));
    });

    test('Windows runner pins to top-right and auto hides to right edge', () {
      final header = File('windows/runner/win32_window.h').readAsStringSync();
      final runner = File('windows/runner/win32_window.cpp').readAsStringSync();
      final flutterWindow = File(
        'windows/runner/flutter_window.cpp',
      ).readAsStringSync();
      final main = File('windows/runner/main.cpp').readAsStringSync();

      expect(header, contains('AlignToTopRightWorkArea'));
      expect(header, contains('StartTopRightAutoHideTimer'));
      expect(header, contains('HandleTopRightAutoHideTimer'));
      expect(header, contains('HideToRightEdge'));
      expect(header, contains('RevealFromRightEdge'));
      expect(header, contains('HandleTopRightDockAfterMove'));
      expect(header, contains('StartEdgeSlideAnimation'));
      expect(header, contains('ApplyEdgeSlideAnimation'));
      expect(header, contains('DockedRightX'));
      expect(header, contains('HiddenRightX'));
      expect(header, contains('is_auto_hidden_'));
      expect(header, contains('is_right_docked_'));
      expect(header, contains('is_sliding_'));
      expect(header, contains('cursor_left_window_at_'));
      expect(header, contains('dock_top_'));
      expect(header, contains('slide_target_hidden_'));

      expect(runner, contains('kTopRightAutoHideTimerId'));
      expect(runner, contains('kAutoHidePollMs = 50'));
      expect(runner, contains('kAutoHideDelayMs = 700'));
      expect(runner, contains('kSlideAnimationMs = 180'));
      expect(runner, contains('kHiddenGripWidth = 6'));
      expect(runner, contains('kRevealHotZoneWidth = 18'));
      expect(runner, contains('kRightDockSnapThreshold = 96'));
      expect(runner, contains('kDragHandleHeight = 34'));
      expect(runner, contains('kChromeButtonStripWidth = 96'));
      expect(runner, contains('MonitorFromWindow'));
      expect(runner, contains('monitor_info.rcWork'));
      expect(runner, contains('GetCursorPos'));
      expect(runner, contains('SetTimer'));
      expect(runner, contains('KillTimer'));
      expect(runner, contains('WM_TIMER'));
      expect(runner, contains('WM_EXITSIZEMOVE'));
      expect(runner, contains('WM_NCHITTEST'));
      expect(runner, contains('HTCAPTION'));
      expect(runner, contains('if (!is_right_docked_)'));
      expect(runner, contains('AlignToTopRightWorkArea();'));
      expect(runner, contains('StartTopRightAutoHideTimer();'));
      expect(runner, contains('HandleTopRightDockAfterMove();'));
      expect(runner, contains('ApplyEdgeSlideAnimation();'));
      expect(runner, contains('StartEdgeSlideAnimation(HiddenRightX('));
      expect(runner, contains('StartEdgeSlideAnimation(DockedRightX('));
      expect(
        runner,
        contains('monitor_info.rcWork.right - window_width'),
      );
      expect(
        runner,
        contains('monitor_info.rcWork.right - kHiddenGripWidth'),
      );
      expect(runner, contains('dock_top_'));
      expect(runner, contains('SWP_NOACTIVATE'));
      expect(runner, contains('WS_POPUP'));
      expect(runner, contains('WS_THICKFRAME'));
      expect(runner, isNot(contains('WS_OVERLAPPEDWINDOW')));

      expect(flutterWindow, contains('MethodChannel'));
      expect(flutterWindow, contains('lockly/window'));
      expect(flutterWindow, contains('minimize'));
      expect(flutterWindow, contains('close'));
      expect(flutterWindow, contains('SW_MINIMIZE'));
      expect(flutterWindow, contains('WM_CLOSE'));

      expect(main, contains('Win32Window::Size size(392, 784);'));
      expect(main, isNot(contains('window_manager')));
    });
  });
}
