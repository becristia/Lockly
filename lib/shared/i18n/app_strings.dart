import 'package:flutter/widgets.dart';
import 'package:secure_box/shared/i18n/app_strings_scope.dart';
import 'package:secure_box/shared/i18n/app_strings_zh.dart';

abstract class AppStrings {
  const AppStrings();

  static AppStrings of(BuildContext context) {
    return AppStringsScope.maybeOf(context) ?? const AppStringsZh();
  }

  String text(String key);

  String get appName;
  String get privacyCoverMessage;
  String get vaultTab;
  String get securityTab;
  String get totpTab;
  String get generatorTab;
  String get settingsTab;
  String get settingsTitle;
  String get languageTitle;
  String get languageSubtitle;
  String get themeTitle;
  String get themeSubtitle;
  String get themeLight;
  String get themeDark;
  String get themeSystem;
  String get vaultTitle;
  String get securitySummaryTitle;
  String get securitySummaryLoading;
  String vaultLocalRecordCount(int count);
  String get encryptedStatus;
  String get localFirstStatus;
  String get searchLabel;
  String get searchHint;
  String searchResultCount(int count);
  String get recentItemsTitle;
  String get allTagsFilter;
  String get addPasswordTooltip;
  String get vaultLoadFailedTitle;
  String get vaultLoadFailedMessage;
  String get retry;
  String get noSearchResultsTitle;
  String get noSearchResultsMessage;
  String get emptyVaultTitle;
  String get emptyVaultMessage;
  String trashTitleWithCount(int count);
  String get missingUsername;
  String get passwordGeneratorTitle;
  String get generatorRulesTitle;
  String get generatorRulesSubtitle;
  String get generatorLengthLabel;
  String get generatorLowercase;
  String get generatorUppercase;
  String get generatorNumbers;
  String get generatorSymbols;
  String get generatorExcludeConfusing;
  String get generatorRequireEveryClass;
  String get generatorResult;
  String get generatorEmptyHint;
  String get generatorStrengthStrong;
  String get generatePassword;
  String get regeneratePassword;
  String get saveThisPassword;
  String get copyPasswordTooltip;
  String get passwordCopied;
  String get copyFailed;
  String get unlockSecurityTitle;
  String get unlockSecuritySubtitle;
  String get changeMasterPassword;
  String get changeMasterPasswordSubtitle;
  String get biometricTitle;
  String get biometricSubtitle;
  String get privacyProtectionTitle;
  String get privacyProtectionSubtitle;
  String get autoLockTitle;
  String get clipboardCleanupTitle;
  String durationLabel(Duration value);
}
