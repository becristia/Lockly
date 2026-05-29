import 'package:secure_box/shared/i18n/app_strings.dart';

class AppStringsEn extends AppStrings {
  const AppStringsEn();

  static const _text = <String, String>{
    'back': 'Back',
    'cancel': 'Cancel',
    'close': 'Close',
    'windowMinimize': 'Minimize',
    'windowExit': 'Exit',
    'confirm': 'Confirm',
    'copy': 'Copy',
    'delete': 'Delete',
    'download': 'Download',
    'edit': 'Edit',
    'keep': 'Keep',
    'manage': 'Manage',
    'preview': 'Preview',
    'refresh': 'Refresh',
    'remove': 'Remove',
    'rename': 'Rename',
    'restore': 'Restore',
    'save': 'Save',
    'saveBusy': 'Saving...',
    'useGeneratedPassword': 'Use this password',
    'working': 'Working',
    'masterPassword': 'Master password',
    'showMasterPassword': 'Show master password',
    'hideMasterPassword': 'Hide master password',
    'showPassword': 'Show password',
    'hidePassword': 'Hide password',
    'requiredMasterPassword': 'Enter the master password',
    'passwordMismatch': 'The master passwords do not match',
    'setupTitle': 'Create master password',
    'setupSubtitle':
        'Your master password is never uploaded and cannot be recovered. Keep it safe.',
    'confirmMasterPassword': 'Confirm master password',
    'passwordMinLength': 'At least 12 characters',
    'showConfirmPassword': 'Show confirmation password',
    'hideConfirmPassword': 'Hide confirmation password',
    'enableBiometricQuickUnlock': 'Enable biometric quick unlock',
    'biometricSetupSubtitle':
        'Biometrics only unlock the local vault quickly. The master password is still required if biometric unlock fails.',
    'createVault': 'Create vault',
    'creatingVault': 'Creating...',
    'setupLocalOnly': 'Master password stays on this device',
    'setupCannotRecover': 'Your master password cannot be viewed or recovered',
    'setupEncrypted': 'Data is protected with end-to-end encryption',
    'privacyAgreementPrefix': 'By continuing, you have read and agree to the ',
    'privacyPolicy': 'Privacy Policy',
    'enterMasterPasswordAgain': 'Enter the master password again',
    'vaultCreatedBiometricFailed':
        'Vault created, but biometric unlock could not be enabled.',
    'createVaultFailed': 'Create failed. Try again later.',
    'unlockTitle': 'Unlock vault',
    'unlockSubtitle':
        'Enter the master password to unlock the local encrypted vault.',
    'unlock': 'Unlock',
    'unlockBusy': 'Unlocking...',
    'useBiometric': 'Use biometrics',
    'unlockRetryHint':
        'After repeated failures, retries are briefly delayed\nto reduce brute-force attempts',
    'unlockRetryFailed': 'Unable to unlock. Try again.',
    'wrongMasterPassword': 'Incorrect master password',
    'waitRetryPrefix': 'Wait',
    'waitRetrySuffix': 'seconds before retrying',
    'useMasterPassword': 'Use the master password to unlock',
    'privacyTermsTitle': 'Terms of Use (Local Vault)',
    'privacyTermsIntro':
        'Welcome to the local vault app. Please read these terms carefully before using the app.',
    'privacySectionService': '1. Service scope',
    'privacySectionServiceBody':
        'This app is a local password manager. Core features include:\n\nPassword records, generation, and organization\nEncrypted local storage\nPassword strength checks and security reminders',
    'privacySectionStorage': '2. Data storage and security',
    'privacySectionStorageBody':
        'The app does not store passwords or sensitive information on any server. All data remains on the user device.\nUser data is protected with end-to-end encryption on this device.\nLocal deletion cannot be undone, so delete carefully.',
    'privacySectionUserDuty': '3. User responsibilities',
    'privacySectionUserDutyBody':
        'Keep your master password and device secure to prevent unauthorized access.\nFollow applicable laws and do not use the app for illegal activity.',
    'privacySectionDisclaimer': '4. Disclaimer',
    'privacySectionDisclaimerBody':
        'The app is not liable for data loss caused by user action, such as forgotten passwords or accidental deletion.\nThe app aims to work reliably, but cannot guarantee fault-free behavior on every device or environment.',
    'privacySectionTermsUpdate': '5. Terms updates',
    'privacySectionTermsUpdateBody':
        'The app may update these terms when needed and notify users in the app.\nContinuing to use the app means accepting the updated terms.',
    'privacyPolicyTitle': 'Privacy Policy (Local Vault)',
    'privacyPolicyIntro':
        'This app values privacy and data security. Please read the following carefully:',
    'privacySectionCollect': '1. Data collection',
    'privacySectionCollectBody':
        'The app does not collect personal information or account information.\nAll user data, including passwords, tags, and notes, is stored locally on the device.',
    'privacySectionUse': '2. Data use',
    'privacySectionUseBody':
        'User data is used only for local password management, password generation, and security checks.\nThe app does not upload data to the cloud or share it with third parties.',
    'privacySectionSecurity': '3. Data security',
    'privacySectionSecurityBody':
        'Passwords and sensitive information are protected with local encryption.\nDeleting local data or uninstalling the app permanently removes all records.',
    'privacySectionThirdParty': '4. Third-party services',
    'privacySectionThirdPartyBody':
        'The app does not depend on third-party servers to process user data.\nIf third-party features such as icons or fonts are integrated, they do not involve sensitive user data.',
    'privacySectionRights': '5. User rights',
    'privacySectionRightsBody':
        'Users can view, modify, or delete local data at any time.\nUsers may stop using or uninstall the app, and local data will be removed with it.',
    'privacySectionPolicyUpdate': '6. Policy updates',
    'privacySectionPolicyUpdateBody':
        'This privacy policy may change as the app evolves.\nContinuing to use the app means accepting the updated policy.',
    'zhLanguage': '中文',
    'enLanguage': 'English',
    'biometricEnableTitle': 'Enable biometrics',
    'biometricEnable': 'Enable',
    'biometricDisableTitle': 'Disable biometrics',
    'biometricDisable': 'Disable',
    'biometricAuthTitle': 'Unlock Lockly',
    'biometricAuthSubtitle': 'Authenticate to unlock your local vault',
    'biometricAuthReason': 'Authenticate to unlock Lockly',
    'biometricDisableMessage':
        'Disabling biometrics removes the DEK copy from the system secure area. Next unlock requires the master password.',
    'biometricEnableFailed':
        'Unable to enable biometrics. Check the master password.',
    'masterPasswordChanged':
        'Master password changed. Biometrics must be enabled again.',
    'autofillSettingsUnavailable': 'Android Autofill settings unavailable',
    'autofillUnsupported': 'Unsupported',
    'autofillEnabled': 'Enabled',
    'autofillDisabled': 'Disabled',
    'exportFailed': 'Export failed. Try again later.',
    'clearLocalVaultTitle': 'Clear local vault',
    'clearLocalVaultMessage':
        'This deletes the local vault and settings from this device and cannot be recovered. Confirm that you have exported a usable backup.',
    'clearLocalVault': 'Clear',
    'androidAutofill': 'Android Autofill',
    'autofillStatus': 'Status',
    'openAutofillSettings': 'Open Android Autofill settings',
    'openAutofillSettingsSubtitle':
        'Enable Lockly as the provider. This stage does not fill saved items yet.',
    'healthTitle': 'Password health',
    'healthSubtitle': 'Check weak, reused, and expired passwords.',
    'healthSubtitleShort': 'Check weak, reused, and expired passwords',
    'tagManagementTitle': 'Tag management',
    'tagManagementSubtitle': 'Manage vault tags.',
    'tagManagementSubtitleShort': 'Manage vault tags',
    'lanExchangeTitle': 'LAN exchange',
    'lanExchangeSubtitle':
        'Move encrypted vault data directly between nearby devices.',
    'lanSendData': 'Send data',
    'lanSendDataSubtitle': 'Create a local transfer QR code for this vault.',
    'lanReceiveData': 'Receive data',
    'lanReceiveDataSubtitle': 'Scan or paste a local transfer payload.',
    'lanSelectRecords': 'Select records',
    'lanSearchRecords': 'Search records',
    'lanIncludeAttachments': 'Include attachments',
    'lanIncludePasswordHistory': 'Include password history',
    'lanPasswordHistoryRisk':
        'Password history can expose old secrets. Include it only when needed.',
    'lanCreateQr': 'Create QR code',
    'lanQrReady': 'QR code ready',
    'lanQrExpires': 'QR expires',
    'lanCancelSession': 'Cancel session',
    'lanCancellingSession': 'Cancelling session...',
    'lanScanQr': 'Scan QR code',
    'lanPasteQrPayload': 'Paste QR payload',
    'lanSourceMasterPassword': 'Source master password',
    'lanSourceMasterPasswordSubtitle':
        'Enter the master password from the sending device.',
    'lanSourcePasswordTitle': 'Source master password for {sender}',
    'lanImporting': 'Importing',
    'lanImportComplete': 'Import complete',
    'lanImportedCount': '{count} imported',
    'lanSkippedCount': '{count} skipped',
    'lanConflicts': 'Conflicts',
    'lanConflictExisting': 'Already exists locally',
    'lanConflictDuplicate': 'Duplicate in transfer',
    'lanQrExpired': 'QR code expired',
    'lanNetworkUnavailable': 'Local network unavailable',
    'lanRecordsLoadFailed': 'Unable to load transferable records. Try again.',
    'lanSessionUnavailable': 'Transfer session unavailable',
    'lanTransferMalformed': 'Transfer payload is invalid or incomplete',
    'lanPackageIntegrityFailed': 'Transfer package integrity check failed',
    'lanSourcePasswordWrong': 'Source master password is incorrect',
    'lanLocalVaultLocked': 'Local vault is locked',
    'lanNoRecordsSelected': 'No records selected',
    'lanSelectedCount': '{count} selected',
    'lanSelectedCountLabel': 'Selected records',
    'lanNoMatchingRecords': 'No matching records',
    'lanHostPort': 'Host',
    'lanScannerUnavailable': 'Scanner unavailable in this environment',
    'lanPastePayloadLabel': 'Transfer payload',
    'lanPayloadAccepted': 'Payload accepted from {sender}',
    'encryptedBackup': 'Encrypted backup',
    'encryptedBackupSubtitle':
        'The backup still requires the master password to restore.',
    'exportEncryptedBackup': 'Export encrypted backup',
    'exportEncryptedBackupSubtitle': 'Export the local encrypted backup JSON.',
    'migrationImport': 'Migration import',
    'migrationImportSubtitle': 'Import Lockly JSON or local CSV exports.',
    'dangerZone': 'Danger zone',
    'dangerZoneSubtitle': 'These actions cannot be undone.',
    'clearLocalVaultSubtitle':
        'Delete the vault and settings from this device.',
    'changeMasterPasswordAdvice':
        'Update your password periodically to improve security.',
    'currentMasterPassword': 'Current master password',
    'newMasterPassword': 'New master password',
    'confirmNewMasterPassword': 'Confirm new master password',
    'masterPasswordCleanupFailed':
        'Master password changed, but biometric cleanup failed. Use the new master password to return to settings and disable biometrics again.',
    'masterPasswordChangeFailed':
        'Master password change failed. Confirm the current master password.',
    'biometricPromptSubtitle':
        'After enabling, fingerprints or face unlock can quickly unlock\nsettings management still requires the master password',
    'localOnlyInfo': 'Information is stored only on this device',
    'backupCopied':
        'Encrypted backup copied. Clipboard will clear in 30 seconds.',
    'backupExportTitle': 'Export encrypted backup',
    'backupExportSubtitle':
        'The backup is encrypted and still requires the matching master password to restore.',
    'reauthenticateExportSubtitle':
        'Enter the master password before exporting encrypted backup material.',
    'reauthenticateClearVaultSubtitle':
        'Enter the master password to confirm local vault deletion.',
    'clearLocalVaultFailed':
        'Could not clear the local vault. Check the master password.',
    'copyBackupConfirmTitle': 'Copy encrypted backup?',
    'copyBackupConfirmMessage':
        'The encrypted backup can be used for offline password guessing if someone gets it. Clipboard will be cleared automatically.',
    'backupPreparedNoPreview':
        'Encrypted backup is ready ({bytes} characters). The full JSON is hidden on screen.',
    'clearClipboardNow': 'Clear clipboard now',
    'clipboardCleared': 'Clipboard cleared.',
    'clipboardClearNoPendingSecret': 'No pending secret clipboard value.',
    'attachmentTooLarge': 'Attachment is too large. Maximum size is {max}.',
    'totpCodeCopied': 'Code copied. Clipboard clears on expiry.',
    'continue': 'Continue',
    'copied': 'Copied',
    'copyBackup': 'Copy backup',
    'email': 'Email',
    'accountPassword': 'Account password',
    'enterEmailAddress': 'Enter an email address',
    'enterAccountPassword': 'Enter the account password',
    'login': 'Login',
    'register': 'Register',
    'ipAddress': 'IP',
    'migrationLocalSubtitle': 'Local import wizard',
    'locklyJson': 'Lockly JSON',
    'csv': 'CSV',
    'backupMasterPassword': 'Backup master password',
    'csvExport': 'CSV export',
    'plaintextCsvExport': 'Plaintext CSV migration import',
    'plaintextCsvWarning':
        'CSV import temporarily processes plaintext passwords and is only for migration from another password manager. The input is cleared after preview; confirm the source is trusted and delete the original CSV after import.',
    'encryptedBackupJson': 'Encrypted backup JSON',
    'csvParseFailed': 'CSV import could not be parsed locally.',
    'csvImportTooLarge': 'CSV import is too large. Maximum size is {max}.',
    'csvImportEmpty': 'CSV import is empty.',
    'csvHeadersMissing': 'CSV headers are missing.',
    'csvQuoteNotClosed': 'CSV has an unclosed quoted field.',
    'importFailed': 'Import failed. Check the source data and try again.',
    'importableRow': 'importable row',
    'importableRows': 'importable rows',
    'import': 'Import',
    'importing': 'Importing',
    'skippedRows': 'skipped rows',
    'securityCenterTitle': 'Security Center',
    'securityCenterSubtitle': 'Vault security overview',
    'securityCenterLocalExchangeTitle': 'Local backup and transfer',
    'securityCenterLocalExchangeSubtitle':
        'Move records by LAN QR codes or receive a local transfer payload.',
    'loadingSecurityPosture': 'Loading security posture',
    'runLocalCheck': 'Run local check',
    'runAgain': 'Run again',
    'checkingLocalVault': 'Checking local vault',
    'localCheckNotRun': 'Local check not run',
    'localCheckFailed': 'Local check failed',
    'migration': 'Migration',
    'autofill': 'Autofill',
    'attachments': 'Attachments',
    'passkeys': 'Passkeys',
    'highRisk': 'High risk',
    'reminder': 'Reminder',
    'healthy': 'Healthy',
    'weakPassword': 'Weak passwords',
    'weakPasswordSubtitle':
        'Password is too short or uses too few character types',
    'healthDetailWeak': 'Password strength is too low',
    'duplicatePassword': 'Reused passwords',
    'duplicatePasswordSubtitle': 'Multiple records use the same password',
    'healthDetailReused': 'Reused by another record',
    'expiredPassword': 'Expired passwords',
    'expiredPasswordSubtitle': 'Not updated for more than 365 days',
    'healthDetailStale': 'Not updated for more than 365 days',
    'similarPassword': 'Similar passwords',
    'similarPasswordSubtitle': 'Password contains the title or website name',
    'healthDetailSimilar': 'Contains the title or website name',
    'neverUpdated': 'Never updated',
    'neverUpdatedSubtitle': 'Password has not changed since creation',
    'healthDetailNeverEdited': 'Never changed since creation',
    'changePassword': 'Change password',
    'vaultHealthy': 'Vault is healthy',
    'noSecurityRisks': 'No security risks found',
    'analysisFailed': 'Analysis failed. Try again.',
    'renameTag': 'Rename tag',
    'newTagName': 'New tag name',
    'renameFailed': 'Rename failed',
    'deleteTag': 'Delete tag',
    'deleteTagMessagePrefix': 'Remove',
    'deleteTagMessageSuffix': 'from all records',
    'deleteFailed': 'Delete failed',
    'emptyTags': 'No tags',
    'trashLoadFailed': 'Unable to read trash. Try again.',
    'permanentDeleteMessagePrefix': 'Permanently delete "',
    'permanentDeleteMessageSuffix': '"? This cannot be undone.',
    'emptyTrashMessagePrefix': 'Permanently delete',
    'emptyTrashMessageSuffix': 'records in trash? This cannot be undone.',
    'justNow': 'Just now',
    'minutesAgo': 'min ago',
    'hoursAgo': 'hours ago',
    'daysAgo': 'days ago',
    'monthsAgo': 'months ago',
    'yearsAgo': 'years ago',
    'restoreFailed': 'Restore failed. Try again.',
    'permanentDelete': 'Permanently delete',
    'emptyTrash': 'Empty trash',
    'clearTrash': 'Empty',
    'clearTrashFailed': 'Empty failed. Try again.',
    'trashEmpty': 'Trash is empty',
    'trashEmptyMessage': 'Deleted password records appear here.',
    'deletedRecords': 'deleted records',
    'healthScore': 'Password health score',
    'totalRecordsPrefix': 'Total',
    'totalRecordsSuffix': 'records',
    'missingUsernameTrash': 'No username',
    'vaultItemMissing': 'This record does not exist or has been deleted.',
    'vaultDetailLoadFailed': 'Unable to load details. Try again.',
    'deleteRecord': 'Delete record',
    'deleteRecordMessage':
        'After deletion, this record will no longer appear in the list. Delete it?',
    'confirmDelete': 'Confirm delete',
    'deleteRecordFailed': 'Delete failed. Try again later.',
    'passwordDetail': 'Password details',
    'exportPassword': 'Export this password',
    'detailUnavailable': 'Unable to show details',
    'titleField': 'Title',
    'websiteHint': 'https://example.com',
    'websiteField': 'Website',
    'usernameField': 'Username',
    'passwordField': 'Password',
    'notesField': 'Notes',
    'tagsField': 'Tags',
    'listSeparator': ', ',
    'notFilled': 'Not filled',
    'hidden': 'Hidden',
    'usernameCopied': 'Username copied.',
    'copyUsername': 'Copy username',
    'passwordHistory': 'Password history',
    'restorePassword': 'Restore password',
    'restorePasswordMessage':
        'Archive the current password into history and replace it with this password?',
    'passwordRestored': 'Password restored',
    'restorePasswordFailed': 'Restore failed',
    'confirmRestore': 'Confirm restore',
    'singleBackupCopied':
        'Single encrypted backup copied. Clipboard will clear in 30 seconds.',
    'exportSinglePassword': 'Export single password',
    'exportSinglePasswordSubtitle':
        'The export is encrypted and contains only the current record. Import requires the matching master password and re-encrypts with the local key.',
    'addAttachment': 'Add attachment',
    'openAttachment': 'Open attachment',
    'deleteAttachment': 'Delete attachment',
    'attachmentOpenFailed': 'Attachment open failed',
    'attachmentDeleteFailed': 'Attachment delete failed',
    'attachmentAddFailed': 'Attachment add failed',
    'noAttachments': 'No attachments',
    'displayNameRequired': 'Display name is required',
    'contentRequired': 'Content is required',
    'displayName': 'Display name',
    'mediaType': 'Media type',
    'content': 'Content',
    'size': 'Size',
    'editPassword': 'Edit password',
    'addPassword': 'Add password',
    'vaultEditLoadFailed': 'Unable to load the record. Try again.',
    'saveFailed': 'Save failed. Try again later.',
    'editUnavailable': 'Unable to edit',
    'titleHint': 'Example: work email',
    'usernameHint': 'Username or email',
    'passwordHint': 'Enter or generate a password',
    'enterTitle': 'Enter a title',
    'enterPassword': 'Enter a password',
    'totpTwoFactor': 'TOTP two-factor authentication',
    'scanQrCode': 'Scan QR code',
    'manualInput': 'Enter manually',
    'totpConfigured': 'TOTP configured',
    'totpPageTitle': 'Authenticator codes',
    'totpPageSubtitle':
        'Use codes linked to vault records or add standalone MFA accounts.',
    'totpHeaderVaultLinked': '{count} linked',
    'totpHeaderStandalone': '{count} standalone',
    'totpHeaderTotal': '{count} total',
    'totpEmptyTitle': 'No authenticator codes yet',
    'totpEmptyMessage':
        'Scan a setup QR code or enter a secret manually to protect an MFA-only account.',
    'totpStandaloneLabel': 'Standalone MFA',
    'totpVaultLinkedLabel': 'Vault linked',
    'totpManualTitle': 'Add standalone MFA',
    'totpEditStandaloneTitle': 'Edit standalone MFA',
    'totpDeleteStandaloneTitle': 'Delete standalone MFA',
    'totpDeleteStandaloneMessage': 'Delete "{title}" from authenticator codes?',
    'totpStandaloneDefaultTitle': 'Standalone MFA',
    'totpStandaloneNameLabel': 'Display name',
    'totpStandaloneNameHint': 'Example: GitHub MFA',
    'totpStandaloneAccountLabel': 'Account',
    'totpStandaloneAccountHint': 'name@example.com',
    'totpStandaloneSecretLabel': 'Secret or otpauth URL',
    'totpSecretInvalid': 'Enter a valid Base32 or otpauth secret',
    'totpSaveStandalone': 'Save MFA',
    'totpSaveFailed': 'Could not save this MFA entry. Try again.',
    'totpScanTitle': 'Scan MFA setup',
    'totpScanSubtitle':
        'Scan an authenticator QR code. The secret is saved only inside the encrypted vault.',
    'totpScannerUnavailable':
        'Scanner unavailable here. Paste the otpauth URL below.',
    'totpPasteOtpAuthLabel': 'otpauth URL or secret',
    'totpPasteOtpAuthHint': 'otpauth://totp/...',
    'totpUsePastedOtpAuth': 'Use pasted value',
    'addNotesHint': 'Add notes...',
    'tagsHint': 'Select or create tags',
    'advancedInfo': 'Advanced information',
    'advancedInfoSubtitle': 'Optional passkey details for advanced use',
    'enterTotpSecret': 'Enter TOTP secret',
    'totpSecretHint': 'Paste Base32 secret',
    'totpSecretHelper': 'Example: JBSWY3DPEHPK3PXP',
    'totpSecretEditHelper': 'Leave blank to keep the current encrypted secret.',
    'cameraPermissionRequired': 'QR scanning requires camera permission',
    'passkeyMetadata': 'Passkey information (optional)',
    'passkeyRemoveConfirmTitle': 'Remove passkey metadata?',
    'passkeyRemoveConfirmMessage':
        'This removes the saved passkey preparation fields from this local record only.',
    'addPasskeyMetadata': 'Add passkey information',
    'editMetadata': 'Edit information',
    'relyingPartyId': 'Website domain ID',
    'rpId': 'Website domain',
    'credential': 'Credential',
    'user': 'User',
    'display': 'Display',
    'algorithm': 'Algorithm',
    'readiness': 'Readiness',
    'exampleDomain': 'example.com',
    'credentialId': 'Credential ID',
    'credentialIdHint': 'base64url credential id',
    'userHandle': 'User handle',
    'publicKeyAlgorithm': 'Public key algorithm',
    'algorithmHint': 'ES256',
    'platform': 'Platform',
    'platformHint': 'android',
    'platformApiReady': 'Platform API ready',
    'platformApiNotEnabled': 'Platform API not enabled',
    'passwordStrength': 'Password strength',
    'passwordStrengthWeak': 'Weak',
    'passwordStrengthFair': 'Fair',
    'passwordStrengthStrongShort': 'Strong',
    'generatorInvalidLength': 'Password length must be positive',
    'generatorNoCharacterClass': 'Select at least one character type',
    'generatorLengthTooShort':
        'Length is too short for the selected character types',
    'generatorFailed': 'Could not generate a password. Check the rules.',
    'requiredField': 'Required',
    'policyMinLength': 'Master password must be at least 12 characters',
    'policyCommonWeak': 'Master password cannot be a common weak password',
    'policyRepeated': 'Master password cannot be made of repeated characters',
    'policyKeyboardWalk': 'Master password cannot be a keyboard sequence',
    'policyUseLongerPassphrase':
        'Use a longer passphrase, or mix uppercase, lowercase, numbers, and symbols',
    'policyStrongPassphrase':
        'Strong: passphrases are easier to remember and harder to guess',
    'policyStrongMixed': 'Strong: length and character mix are good',
    'policyFairImprove': 'Fair: keep strengthening the master password',
    'policyEntryEmpty': 'Password cannot be empty',
    'policyEntryMinLength': 'Use at least 8 characters',
    'policyEntryCommonWeak': 'Password is too common or easy to guess',
    'policyEntryStrong': 'Strong: suitable for a saved record password',
    'policyEntryFair': 'Fair: usable, but consider strengthening it',
    'policyEntryWeak': 'Weak: consider generating a stronger password',
    'copiedLocally': 'Copied locally',
    'copyUnavailable': 'Copy unavailable',
    'localCheckNotRunDetail':
        'Run an explicit on-device check before decrypting saved items for analysis.',
    'localCheckFailedDetail':
        'The vault stayed local; try again after confirming it is unlocked.',
    'healthScoreSuffix': 'health score',
    'savedItemsCheckedLocally': 'saved items checked locally.',
    'weakCountLabel': 'weak',
    'reusedCountLabel': 'reused',
    'staleCountLabel': 'stale',
    'foundLocallySuffix': 'passwords found locally.',
    'revokedStatus': 'revoked',
    'roadmapMigrationDetail': 'Guided importer and export checks.',
    'roadmapAutofillDetail': 'System autofill posture and setup status.',
    'roadmapAttachmentsDetail': 'Encrypted file storage readiness.',
    'roadmapPasskeysDetail': 'Passkey vault support entry point.',
  };

  @override
  String text(String key) =>
      _text[key] ?? (throw ArgumentError.value(key, 'key', 'Unknown text key'));

  @override
  String get appName => 'Lockly';
  @override
  String get privacyCoverMessage => 'Privacy protection enabled...';
  @override
  String get vaultTab => 'Vault';
  @override
  String get securityTab => 'Security';
  @override
  String get totpTab => 'TOTP';
  @override
  String get generatorTab => 'Generator';
  @override
  String get settingsTab => 'Settings';
  @override
  String get settingsTitle => 'Settings';
  @override
  String get languageTitle => 'Language';
  @override
  String get languageSubtitle => 'Choose the display language for Lockly.';
  @override
  String get themeTitle => 'Theme';
  @override
  String get themeSubtitle => 'Choose light, dark, or system theme.';
  @override
  String get themeLight => 'Light';
  @override
  String get themeDark => 'Dark';
  @override
  String get themeSystem => 'System';
  @override
  String get vaultTitle => 'Vault';
  @override
  String get securitySummaryTitle => 'Local vault';
  @override
  String get securitySummaryLoading => 'Verifying local encrypted records';
  @override
  String vaultLocalRecordCount(int count) => '$count records stored locally';
  @override
  String get encryptedStatus => 'Encrypted';
  @override
  String get localFirstStatus => 'Local first';
  @override
  String get searchLabel => 'Search';
  @override
  String get searchHint => 'Search records';
  @override
  String searchResultCount(int count) => 'Search results $count';
  @override
  String get recentItemsTitle => 'Recently used';
  @override
  String get allTagsFilter => 'All';
  @override
  String get addPasswordTooltip => 'Add password';
  @override
  String get vaultLoadFailedTitle => 'Load failed';
  @override
  String get vaultLoadFailedMessage =>
      'Unable to read the vault list. Try again.';
  @override
  String get retry => 'Retry';
  @override
  String get noSearchResultsTitle => 'No matches';
  @override
  String get noSearchResultsMessage => 'Try a shorter keyword.';
  @override
  String get emptyVaultTitle => 'No saved passwords yet';
  @override
  String get emptyVaultMessage =>
      'Use the add button to create your first record.';
  @override
  String trashTitleWithCount(int count) => 'Trash ($count)';
  @override
  String get missingUsername => 'No username';
  @override
  String get passwordGeneratorTitle => 'Password generator';
  @override
  String get generatorRulesTitle => 'Generation rules';
  @override
  String get generatorRulesSubtitle =>
      'By default, each selected character class appears at least once.';
  @override
  String get generatorLengthLabel => 'Length';
  @override
  String get generatorLowercase => 'Lowercase';
  @override
  String get generatorUppercase => 'Uppercase';
  @override
  String get generatorNumbers => 'Numbers';
  @override
  String get generatorSymbols => 'Symbols';
  @override
  String get generatorExcludeConfusing => 'Exclude confusing characters';
  @override
  String get generatorRequireEveryClass => 'Require each class';
  @override
  String get generatorResult => 'Generated result';
  @override
  String get generatorEmptyHint =>
      'Generate a password, then save it directly to a new record.';
  @override
  String get generatorStrengthStrong => 'Strong';
  @override
  String get generatePassword => 'Generate password';
  @override
  String get regeneratePassword => 'Regenerate';
  @override
  String get saveThisPassword => 'Save this password';
  @override
  String get copyPasswordTooltip => 'Copy password';
  @override
  String get passwordCopied =>
      'Password copied. Clipboard will clear in 30 seconds.';
  @override
  String get copyFailed => 'Copy failed. Try again.';
  @override
  String get unlockSecurityTitle => 'Unlock security';
  @override
  String get unlockSecuritySubtitle =>
      'Manage the master password and biometric unlock.';
  @override
  String get changeMasterPassword => 'Change master password';
  @override
  String get changeMasterPasswordSubtitle =>
      'Only re-encrypts the DEK, not every vault item.';
  @override
  String get biometricTitle => 'Biometrics';
  @override
  String get biometricSubtitle =>
      'Falls back to the master password when biometric unlock fails.';
  @override
  String get privacyProtectionTitle => 'Privacy protection';
  @override
  String get privacyProtectionSubtitle =>
      'Control auto-lock and clipboard cleanup timing.';
  @override
  String get autoLockTitle => 'Auto-lock';
  @override
  String get clipboardCleanupTitle => 'Clipboard cleanup';
  @override
  String durationLabel(Duration value) {
    if (value.inMinutes >= 1) {
      return '${value.inMinutes} min';
    }
    return '${value.inSeconds} sec';
  }
}
