import 'package:flutter/widgets.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';

class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  final AppStrings strings;

  static AppStrings? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppStringsScope>()
        ?.strings;
  }

  static AppStrings of(BuildContext context) {
    final strings = maybeOf(context);
    if (strings == null) {
      throw StateError('AppStringsScope is missing above this context.');
    }
    return strings;
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) {
    return strings.runtimeType != oldWidget.strings.runtimeType;
  }
}
