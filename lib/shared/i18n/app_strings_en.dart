import 'package:secure_box/shared/i18n/app_strings.dart';

class AppStringsEn extends AppStrings {
  const AppStringsEn();

  static const _text = <String, String>{
    'back': 'Back',
    'cancel': 'Cancel',
    'close': 'Close',
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
    'cloudNotConnected': 'Not connected',
    'cloudConnected': 'Connected',
    'cloudRegisteredConnected': 'Registered and connected',
    'cloudSyncConflictsDetected': 'Sync conflicts detected; imported',
    'cloudEncryptedUpdates': 'encrypted updates',
    'cloudUnresolvedConflicts': 'unresolved conflicts',
    'cloudSyncedImported': 'Synced; imported',
    'cloudDownloadedImported': 'Downloaded and imported',
    'cloudEncryptedRecords': 'encrypted records',
    'cloudDeviceCountSuffix': 'cloud device(s)',
    'cloudDeviceRenamed': 'Device renamed',
    'cloudDeviceRevoked': 'Device revoked',
    'cloudUnavailable': 'Cloud sync unavailable',
    'cloudLoginRequired': 'Sign in to cloud sync first.',
    'cloudRegisterValidationError':
        'Registration details are invalid. Check the email format and use a cloud account password of at least 12 characters.',
    'cloudInvalidCredentials': 'Email or cloud account password is incorrect.',
    'cloudUserDisabled': 'This cloud account is disabled.',
    'cloudNetworkFailed':
        'Cannot reach the cloud sync service. Check the backend URL and network.',
    'cloudActionFailed': 'Cloud sync action failed. Try again later.',
    'cloudSyncVaultTitle': 'Sync encrypted vault',
    'cloudSync': 'Sync',
    'cloudDownloadVaultTitle': 'Download cloud vault',
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
    'cloudSyncTitle': 'Cloud sync',
    'cloudSyncSubtitle':
        'Sync encrypted vault data through your backend account.',
    'cloudSyncStatus': 'Cloud sync status',
    'cloudLogin': 'Cloud login',
    'cloudLoginSubtitle': 'Use a separate backend account password.',
    'cloudRegister': 'Cloud register',
    'cloudRegisterSubtitle': 'Create a backend account for sync.',
    'cloudDownloadVault': 'Download cloud vault',
    'cloudDevices': 'Cloud devices',
    'cloudDevicesSubtitle': 'List trusted devices for this account.',
    'cloudLogout': 'Cloud logout',
    'cloudLogoutSubtitle': 'Clear cloud tokens from this device.',
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
    'cloudMasterPasswordPromptSubtitle':
        'Enter the local master password to process encrypted sync data. It is never uploaded or saved on the backend.',
    'localOnlyInfo': 'Information is stored only on this device',
    'backupCopied':
        'Encrypted backup copied. Clipboard will clear in 30 seconds.',
    'backupExportTitle': 'Export encrypted backup',
    'backupExportSubtitle':
        'The backup is encrypted and still requires the matching master password to restore.',
    'copied': 'Copied',
    'copyBackup': 'Copy backup',
    'email': 'Email',
    'accountPassword': 'Account password',
    'enterEmailAddress': 'Enter an email address',
    'enterAccountPassword': 'Enter the account password',
    'login': 'Login',
    'register': 'Register',
    'noCloudDevices': 'No cloud devices',
    'renameDevice': 'Rename device',
    'deviceName': 'Device name',
    'enterDeviceName': 'Enter a device name',
    'unknownPlatform': 'Unknown platform',
    'lastSync': 'Last sync',
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
    'importFailed': 'Import failed. Check the source data and try again.',
    'importableRow': 'importable row',
    'importableRows': 'importable rows',
    'import': 'Import',
    'importing': 'Importing',
    'skippedRows': 'skipped rows',
    'securityCenterTitle': 'Security Center',
    'securityCenterSubtitle': 'Vault security overview',
    'syncConflicts': 'Sync conflicts',
    'downloadLatestEncryptedVault': 'Download latest encrypted vault',
    'masterPasswordConfirmationFailed': 'Master password confirmation failed',
    'cloudDownloadFailed': 'Cloud download failed',
    'confirmMasterPasswordTitle': 'Confirm master password',
    'loadingSecurityPosture': 'Loading security posture',
    'runLocalCheck': 'Run local check',
    'runAgain': 'Run again',
    'reviewConflicts': 'Review conflicts',
    'localRevision': 'Local revision',
    'cloudRevision': 'Cloud revision',
    'localTimestamp': 'Local timestamp',
    'encryptedBlob': 'Encrypted blob',
    'checkingLocalVault': 'Checking local vault',
    'localCheckNotRun': 'Local check not run',
    'localCheckFailed': 'Local check failed',
    'conflictStateUnavailable': 'Conflict state unavailable',
    'noUnresolvedConflicts': 'No unresolved conflicts',
    'deviceListUnavailable': 'Device list unavailable',
    'noCloudDevicesConnected': 'No cloud devices connected',
    'emergencyAccessUnavailable': 'Emergency access unavailable',
    'deviceTrust': 'Device trust',
    'emergencyAccess': 'Emergency access',
    'migration': 'Migration',
    'autofill': 'Autofill',
    'attachments': 'Attachments',
    'passkeys': 'Passkeys',
    'emergency': 'Emergency',
    'highRisk': 'High risk',
    'reminder': 'Reminder',
    'healthy': 'Healthy',
    'weakPassword': 'Weak passwords',
    'weakPasswordSubtitle':
        'Password is too short or uses too few character types',
    'duplicatePassword': 'Reused passwords',
    'duplicatePasswordSubtitle': 'Multiple records use the same password',
    'expiredPassword': 'Expired passwords',
    'expiredPasswordSubtitle': 'Not updated for more than 365 days',
    'similarPassword': 'Similar passwords',
    'similarPasswordSubtitle': 'Password contains the title or website name',
    'neverUpdated': 'Never updated',
    'neverUpdatedSubtitle': 'Password has not changed since creation',
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
    'addNotesHint': 'Add notes...',
    'tagsHint': 'Select or create tags',
    'enterTotpSecret': 'Enter TOTP secret',
    'totpSecretHint': 'Paste Base32 secret',
    'totpSecretHelper': 'Example: JBSWY3DPEHPK3PXP',
    'cameraPermissionRequired': 'QR scanning requires camera permission',
    'passkeyMetadata': 'Passkey metadata',
    'addPasskeyMetadata': 'Add passkey metadata',
    'editMetadata': 'Edit metadata',
    'relyingPartyId': 'Relying party ID',
    'rpId': 'RP ID',
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
    'emergencyKeyGenerationFailed': 'Emergency key generation failed',
    'emergencyContactRequiredFields':
        'Email, public key, and fingerprint are required',
    'emergencyContactKeyRejected': 'Contact key details are not accepted',
    'emergencyContactCreationFailed': 'Contact creation failed',
    'emergencyContactRevokeFailed': 'Contact revoke failed',
    'emergencyChooseActiveContact': 'Choose an active contact',
    'emergencyWaitingPeriodInvalid': 'Waiting period must be 1 to 2160 hours',
    'emergencyRecoveryPlaintextRequired':
        'Recovery package plaintext is required',
    'emergencyRecoveryPlaintextTooLarge':
        'Recovery package plaintext must be 64 KiB or less',
    'emergencyGrantCreationFailed': 'Grant creation failed',
    'emergencyGrantAcceptFailed': 'Grant accept failed',
    'emergencyAccessRequestFailed': 'Access request failed',
    'emergencyCancelFailed': 'Cancel failed',
    'emergencyGrantRevokeFailed': 'Grant revoke failed',
    'emergencyPackageDownloadFailed': 'Package download failed',
    'emergencyHeaderSubtitle':
        'Manage recovery contacts, encrypted grants, and local recipient package decryption.',
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
    'cloudSyncMissingDetail':
        'Cloud sync is not connected or local sync state is missing.',
    'unresolvedConflict': 'unresolved conflict(s)',
    'syncNoPendingConflictsDetail':
        'Local encrypted sync state has no pending conflict records.',
    'syncReviewMetadataDetail':
        'Review safe metadata and download the latest encrypted vault when ready.',
    'deviceTrustSignInDetail':
        'Sign in to cloud sync to review trusted devices.',
    'activeDevicesTrusted': 'active devices trusted',
    'deviceCanRegisterAfterSignIn':
        'Cloud sync can register this device when you sign in.',
    'deviceRiskSummarySuffix': 'risk indicator(s):',
    'untrustedDevices': 'untrusted',
    'missingDeviceMetadata': 'missing metadata',
    'staleDeviceSync': 'stale sync',
    'emergencyMetadataUnavailableDetail':
        'Cloud sync is not connected or emergency metadata is unavailable.',
    'revokedStatus': 'revoked',
    'emergencyStatusActive': 'active',
    'emergencyStatusRevoked': 'revoked',
    'emergencyStatusPendingAcceptance': 'pending acceptance',
    'emergencyStatusAccessRequested': 'access requested',
    'emergencyStatusReadyForDownload': 'ready for download',
    'emergencyStatusCancelled': 'cancelled',
    'emergencyStatusDownloaded': 'downloaded',
    'waitingHoursSuffix': 'h wait',
    'activeContactCount': 'active contact(s)',
    'configuredGrantCount': 'grant(s) configured for delayed recovery.',
    'roadmapMigrationDetail': 'Guided importer and export checks.',
    'roadmapAutofillDetail': 'System autofill posture and setup status.',
    'roadmapAttachmentsDetail': 'Encrypted file storage readiness.',
    'roadmapPasskeysDetail': 'Passkey vault support entry point.',
    'roadmapEmergencyDetail': 'Recovery contacts and delayed access.',
    'emergencyLoading': 'Loading emergency access',
    'revokeContact': 'Revoke contact',
    'revokeContactMessage': 'Revoke emergency access setup for this contact?',
    'acceptEmergencyGrant': 'Accept emergency grant',
    'recipientKeyFingerprint': 'Recipient key fingerprint',
    'cancelRequest': 'Cancel request',
    'cancelRequestMessage': 'Cancel the pending emergency access request?',
    'revokeGrant': 'Revoke grant',
    'revokeGrantMessage': 'Revoke this emergency grant?',
    'recipientSetupKey': 'Recipient setup key',
    'generateLocalKeyPair': 'Generate local key pair',
    'publicKey': 'Public key',
    'fingerprint': 'Fingerprint',
    'privateKeyLocalOnly': 'Private key (local only)',
    'createContact': 'Create contact',
    'recipientEmail': 'Recipient email',
    'recipientPublicKey': 'Recipient public key',
    'optionalLabel': 'Label (optional)',
    'createEncryptedGrant': 'Create encrypted grant',
    'activeContact': 'Active contact',
    'waitingPeriodHours': 'Waiting period (hours)',
    'localRecoveryPackagePlaintext': 'Local recovery package plaintext',
    'localRecoveryPackageHelper': '64 KiB max. Cleared after submit.',
    'encryptAndCreateGrant': 'Encrypt and create grant',
    'contacts': 'Contacts',
    'contactsUnavailable': 'Emergency contacts unavailable',
    'noContacts': 'No emergency contacts',
    'grants': 'Grants',
    'grantsUnavailable': 'Emergency grants unavailable',
    'noGrants': 'No emergency grants',
    'accept': 'Accept',
    'requestAccess': 'Request access',
    'localDecryptFailed': 'Local decrypt failed',
    'emergencyPackage': 'Emergency package',
    'grant': 'Grant',
    'packageFingerprint': 'Package fingerprint',
    'recipientPrivateKeyLocalOnly': 'Recipient private key (local only)',
    'decryptLocally': 'Decrypt locally',
    'decryptedPackage': 'Decrypted package',
    'packageAad': 'Package AAD',
    'encryptedPackageEnvelope': 'Encrypted package envelope',
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
