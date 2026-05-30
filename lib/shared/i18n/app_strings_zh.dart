import 'package:secure_box/shared/i18n/app_strings.dart';

class AppStringsZh extends AppStrings {
  const AppStringsZh();

  static const _text = <String, String>{
    'back': '返回',
    'cancel': '取消',
    'close': '关闭',
    'windowMinimize': '最小化到托盘',
    'windowExit': '退出',
    'lockNow': '立即锁定',
    'confirm': '确认',
    'copy': '复制',
    'delete': '删除',
    'download': '下载',
    'edit': '编辑',
    'keep': '保留',
    'manage': '管理',
    'preview': '预览',
    'refresh': '刷新',
    'remove': '移除',
    'rename': '重命名',
    'restore': '恢复',
    'save': '保存',
    'saveBusy': '保存中...',
    'useGeneratedPassword': '使用此密码',
    'working': '处理中',
    'masterPassword': '主密码',
    'showMasterPassword': '显示主密码',
    'hideMasterPassword': '隐藏主密码',
    'showPassword': '显示密码',
    'hidePassword': '隐藏密码',
    'requiredMasterPassword': '请输入主密码',
    'passwordMismatch': '两次输入的主密码不一致',
    'setupTitle': '创建主密码',
    'setupSubtitle': 'Lockly 不保存主密码，主密码也无法恢复。请务必牢记。',
    'confirmMasterPassword': '确认主密码',
    'passwordMinLength': '至少 12 个字符',
    'showConfirmPassword': '显示确认密码',
    'hideConfirmPassword': '隐藏确认密码',
    'enableBiometricQuickUnlock': '启用生物识别快速解锁',
    'biometricSetupSubtitle': '生物识别仅用于快速解锁本地密码库，失败仍需输入主密码。',
    'createVault': '创建密码库',
    'creatingVault': '创建中...',
    'setupLocalOnly': 'Lockly 不保存主密码',
    'setupCannotRecover': '无法查看或恢复你的主密码',
    'setupEncrypted': '数据采用端到端加密保护',
    'privacyAgreementPrefix': '继续操作即表示你已经阅读并同意 ',
    'privacyPolicy': '隐私政策',
    'enterMasterPasswordAgain': '请再次输入主密码',
    'vaultCreatedBiometricFailed': '密码库已创建，但未能启用生物识别。',
    'createVaultFailed': '创建失败，请稍后重试',
    'unlockTitle': '解锁密码库',
    'unlockSubtitle': '输入主密码以解锁本地加密密码库。',
    'unlock': '解锁',
    'unlockBusy': '解锁中...',
    'useBiometric': '使用指纹/面容解锁',
    'unlockRetryHint': '连续输错后会短暂延迟重试\n以降低暴力尝试风险',
    'unlockRetryFailed': '暂时无法解锁，请重试',
    'wrongMasterPassword': '主密码不正确',
    'waitRetryPrefix': '请等待',
    'waitRetrySuffix': '秒后重试',
    'useMasterPassword': '请使用主密码解锁',
    'privacyTermsTitle': '用户协议（本地密码库）',
    'privacyTermsIntro':
        '欢迎使用"本地密码库"应用（以下简称"本应用"）。在使用本应用前，请仔细阅读以下协议条款，确保您充分理解并同意所有内容后再使用本应用。',
    'privacySectionService': '1. 服务内容',
    'privacySectionServiceBody':
        '本应用为本地密码管理工具，主要功能包括：\n\n密码记录、生成、分类管理\n本地数据加密存储\n密码强度评估及安全提示',
    'privacySectionStorage': '2. 数据存储与安全',
    'privacySectionStorageBody':
        '本应用不在任何服务器上存储用户密码或敏感信息，所有数据仅保存在用户设备本地。\n用户数据通过端到端加密技术保护，保证数据在本机安全。\n密码本地删除操作一旦执行不可恢复，请用户谨慎操作。',
    'privacySectionUserDuty': '3. 用户义务',
    'privacySectionUserDutyBody':
        '用户须妥善保管主密码及设备，避免他人获取访问权限。\n遵守当地法律法规，确保不利用本应用进行非法活动。',
    'privacySectionDisclaimer': '4. 免责条款',
    'privacySectionDisclaimerBody':
        '本应用对因用户操作不当（如密码遗忘或误删）造成的任何数据丢失不承担责任。\n本应用在合理范围内保障功能正常，但不保证在所有设备及环境下完全无故障。',
    'privacySectionTermsUpdate': '5. 协议修改',
    'privacySectionTermsUpdateBody':
        '本应用有权在必要时更新用户协议，更新内容将通过应用内提示通知用户。\n用户继续使用应用即视为接受更新后的协议。',
    'privacyPolicyTitle': '隐私政策（本地密码库）',
    'privacyPolicyIntro': '本应用重视用户隐私与数据安全，请仔细阅读以下内容：',
    'privacySectionCollect': '1. 数据收集',
    'privacySectionCollectBody':
        '本应用不收集任何个人信息或账号信息。\n所有用户数据（包括密码、标签、备注等）均存储在本地设备。',
    'privacySectionUse': '2. 数据使用',
    'privacySectionUseBody': '用户数据仅用于本地密码管理、密码生成及安全评估。\n本应用不会将数据上传云端或共享给第三方。',
    'privacySectionSecurity': '3. 数据安全',
    'privacySectionSecurityBody':
        '用户密码和敏感信息通过本地加密方式保护。\n删除本地数据或卸载应用将永久删除所有记录，不可恢复。',
    'privacySectionThirdParty': '4. 第三方服务',
    'privacySectionThirdPartyBody':
        '本应用不依赖第三方服务器处理用户数据。\n如果集成第三方功能（如图标或字体包），不会涉及用户敏感信息。',
    'privacySectionRights': '5. 用户权利',
    'privacySectionRightsBody':
        '用户可随时查看、修改或删除本地数据。\n用户可选择退出应用或卸载应用，所有本地数据将随之删除。',
    'privacySectionPolicyUpdate': '6. 政策更新',
    'privacySectionPolicyUpdateBody':
        '本隐私政策可能随应用版本更新而调整。\n用户继续使用应用即表示同意更新后的隐私政策。',
    'zhLanguage': '中文',
    'enLanguage': 'English',
    'biometricEnableTitle': '开启生物识别',
    'biometricEnable': '开启',
    'biometricDisableTitle': '关闭生物识别',
    'biometricDisable': '关闭',
    'biometricAuthTitle': '指纹/面容解锁 Lockly',
    'biometricAuthSubtitle': '使用系统生物识别解锁本地密码库',
    'biometricAuthReason': '使用指纹或面容解锁 Lockly',
    'biometricDisableMessage': '关闭后会删除系统安全区中的 DEK 副本，下次需要输入主密码。',
    'biometricEnableFailed': '无法开启生物识别，请确认主密码。',
    'masterPasswordChanged': '主密码已修改，生物识别需要重新开启。',
    'autofillSettingsUnavailable': 'Android 自动填充设置不可用',
    'autofillUnsupported': '不支持',
    'autofillEnabled': '已启用',
    'autofillDisabled': '已禁用',
    'exportFailed': '导出失败，请稍后重试。',
    'clearLocalVaultTitle': '清除本地密码库',
    'clearLocalVaultMessage': '此操作会删除本机密码库和设置，无法找回。请确认已经导出可用备份。',
    'clearLocalVault': '清除',
    'androidAutofill': 'Android 自动填充',
    'autofillStatus': '状态',
    'openAutofillSettings': '打开 Android 自动填充设置',
    'openAutofillSettingsSubtitle': '启用 Lockly 作为系统填充服务。当前阶段不会直接填充已保存条目。',
    'healthTitle': '密码健康',
    'healthSubtitle': '检测弱密码、重复密码和过期密码。',
    'healthSubtitleShort': '检测弱密码、重复密码和过期密码',
    'tagManagementTitle': '标签管理',
    'tagManagementSubtitle': '管理密码库标签。',
    'tagManagementSubtitleShort': '管理密码库标签',
    'lanExchangeTitle': '局域网交换',
    'lanExchangeSubtitle': '在附近设备之间进行一次性局域网传输，不会持续同步。',
    'lanSendData': '发送数据',
    'lanSendDataSubtitle': '为当前密码库创建一次性本地传输 QR 码。',
    'lanReceiveData': '接收数据',
    'lanReceiveDataSubtitle': '扫描或粘贴一次性本地传输内容。',
    'lanSelectRecords': '选择记录',
    'lanSearchRecords': '搜索记录',
    'lanIncludeAttachments': '包含附件',
    'lanIncludePasswordHistory': '包含密码历史',
    'lanPasswordHistoryRisk': '密码历史可能暴露旧密码，仅在需要时包含。',
    'lanCreateQr': '创建 QR 码',
    'lanQrReady': 'QR 码已就绪',
    'lanQrExpires': 'QR 码过期时间',
    'lanCancelSession': '取消会话',
    'lanCancellingSession': '正在取消会话...',
    'lanScanQr': '扫描 QR 码',
    'lanPasteQrPayload': '粘贴 QR 内容',
    'lanSourceMasterPassword': '来源主密码',
    'lanSourceMasterPasswordSubtitle': '请输入发送设备上的主密码。',
    'lanImportFromSenderTitle': '从 {sender} 导入',
    'lanOneTimeImportSubtitle':
        '这是一种由二维码会话密钥保护的一次性传输。你的本地主密码不会被更改，发送设备上的数据也不会被删除。',
    'lanPackageUnlockFailed': '无法解锁此传输包。请让发送端重新创建二维码。',
    'lanImporting': '正在导入',
    'lanImportComplete': '导入完成',
    'lanImportedCount': '已导入 {count} 条',
    'lanSkippedCount': '已跳过 {count} 条',
    'lanConflicts': '冲突',
    'lanConflictExisting': '本地已存在',
    'lanConflictDuplicate': '传输内容中重复',
    'lanQrExpired': 'QR 码已过期',
    'lanNetworkUnavailable': '局域网不可用',
    'lanRecordsLoadFailed': '暂时无法读取可发送记录，请重试。',
    'lanSessionUnavailable': '传输会话不可用',
    'lanTransferMalformed': '传输内容无效或不完整',
    'lanPackageIntegrityFailed': '传输包完整性校验失败',
    'lanSourcePasswordWrong': '来源主密码不正确',
    'lanLocalVaultLocked': '本地密码库已锁定',
    'lanNoRecordsSelected': '未选择记录',
    'lanSourcePasswordTitle': '{sender} 的来源主密码',
    'lanSelectedCount': '已选择 {count} 条',
    'lanSelectedCountLabel': '已选择记录',
    'lanNoMatchingRecords': '没有匹配记录',
    'lanHostPort': '主机',
    'lanScannerUnavailable': '当前环境不可用扫描器',
    'lanPastePayloadLabel': '传输内容',
    'lanPayloadAccepted': '已接受来自 {sender} 的内容',
    'encryptedBackup': '加密备份',
    'encryptedBackupSubtitle': '备份仍需主密码才能恢复。',
    'exportEncryptedBackup': '导出加密备份',
    'exportEncryptedBackupSubtitle': '导出本地加密备份 JSON。',
    'migrationImport': '迁移导入',
    'migrationImportSubtitle': '导入 Lockly JSON 或本地 CSV 导出。',
    'dangerZone': '危险操作',
    'dangerZoneSubtitle': '这些操作不可撤销。',
    'clearLocalVaultSubtitle': '删除本机密码库和设置。',
    'changeMasterPasswordAdvice': '建议定期更新密码以提升安全性。',
    'currentMasterPassword': '当前主密码',
    'newMasterPassword': '新主密码',
    'confirmNewMasterPassword': '确认新主密码',
    'masterPasswordCleanupFailed': '主密码已修改，但生物识别清理失败。请使用新主密码重新进入设置并重试关闭生物识别。',
    'masterPasswordChangeFailed': '主密码修改失败，请确认当前主密码。',
    'biometricPromptSubtitle': '启用后，可使用指纹或面部快速解锁\n仍需输入主密码以管理设置',
    'localOnlyInfo': 'Lockly 不保存主密码，主密码无法恢复',
    'settingsLoadFailed': '设置加载失败，请重试。',
    'backupCopied': '加密备份已复制，30 秒后将自动清理剪贴板。',
    'backupExportTitle': '导出加密备份',
    'backupExportSubtitle': '备份内容已加密，恢复时仍需要对应主密码。',
    'backupExportWizardSubtitle': '准备、校验并复制本地加密备份。',
    'backupExportPrepareDetail':
        '输入本地主密码以准备加密备份。完整 JSON 会保持隐藏，只有在你明确复制时才进入剪贴板。',
    'backupExportPrepare': '准备备份',
    'backupExportPreparing': '正在准备备份',
    'backupExportReadyDetail': '加密备份已校验并准备好复制。请将它保存在私密且独立于本设备的位置。',
    'backupExportItems': '密码条目',
    'backupExportAttachments': '附件',
    'backupExportHistory': '密码历史',
    'backupExportSize': '备份大小',
    'reauthenticateExportSubtitle': '导出加密备份材料前，请先输入主密码。',
    'reauthenticateClearVaultSubtitle': '请输入主密码以确认清除本地密码库。',
    'clearLocalVaultFailed': '无法清除本地密码库，请确认主密码。',
    'copyBackupConfirmTitle': '复制加密备份？',
    'copyBackupConfirmMessage': '加密备份一旦泄露，可能被用于离线猜测主密码。剪贴板会自动清理。',
    'backupPreparedNoPreview': '加密备份已准备好（{bytes} 个字符）。完整 JSON 已在屏幕上隐藏。',
    'clearClipboardNow': '立即清理剪贴板',
    'clipboardCleared': '剪贴板已清理。',
    'clipboardClearNoPendingSecret': '没有待清理的敏感剪贴板内容。',
    'attachmentTooLarge': '附件过大，最大支持 {max}。',
    'totpCodeCopied': '验证码已复制，将在到期时清理剪贴板。',
    'continue': '继续',
    'copied': '已复制',
    'copyBackup': '复制备份',
    'email': '邮箱',
    'accountPassword': '账户密码',
    'enterEmailAddress': '请输入邮箱地址',
    'enterAccountPassword': '请输入账户密码',
    'login': '登录',
    'register': '注册',
    'ipAddress': 'IP',
    'migrationLocalSubtitle': '本地导入向导',
    'locklyJson': 'Lockly JSON',
    'csv': 'CSV',
    'backupMasterPassword': '备份主密码',
    'csvExport': 'CSV 导出',
    'plaintextCsvExport': '明文 CSV 迁移导入',
    'plaintextCsvWarning':
        'CSV 导入会短暂处理明文密码，仅用于从其他密码管理器迁移。预览后输入框会立即清空；请确认来源可信，导入完成后删除原始 CSV 文件。',
    'encryptedBackupJson': '加密备份 JSON',
    'requiredEncryptedBackupJson': '请粘贴加密备份 JSON',
    'requiredBackupMasterPassword': '请输入备份主密码',
    'csvParseFailed': '无法在本地解析 CSV 导入内容。',
    'csvImportTooLarge': 'CSV 导入内容过大，最大支持 {max}。',
    'csvImportEmpty': 'CSV 导入内容为空。',
    'csvHeadersMissing': 'CSV 表头缺失。',
    'csvQuoteNotClosed': 'CSV 存在未闭合的引号字段。',
    'importFailed': '导入失败。请检查源数据后重试。',
    'importableRow': '可导入行',
    'importableRows': '可导入行',
    'import': '导入',
    'importing': '导入中',
    'skippedRows': '跳过的行',
    'securityCenterTitle': '安全中心',
    'securityCenterSubtitle': '密码库安全概览',
    'securityCenterLocalExchangeTitle': '本地备份与转移',
    'securityCenterLocalExchangeSubtitle': '通过局域网二维码转移记录，或接收本地传输载荷。',
    'loadingSecurityPosture': '正在加载安全状态',
    'runLocalCheck': '运行本地检查',
    'runAgain': '再次运行',
    'checkingLocalVault': '正在检查本地密码库',
    'localCheckNotRun': '尚未运行本地检查',
    'localCheckFailed': '本地检查失败',
    'migration': '迁移',
    'autofill': '自动填充',
    'attachments': '附件',
    'passkeys': '通行密钥',
    'highRisk': '高风险',
    'reminder': '提醒',
    'healthy': '健康',
    'weakPassword': '弱密码',
    'weakPasswordSubtitle': '密码长度不足或字符类型单一',
    'healthDetailWeak': '密码强度不足',
    'duplicatePassword': '重复密码',
    'duplicatePasswordSubtitle': '多个条目使用相同密码',
    'healthDetailReused': '与其他条目重复',
    'expiredPassword': '过期密码',
    'expiredPasswordSubtitle': '超过 365 天未更新',
    'healthDetailStale': '超过 365 天未更新',
    'similarPassword': '相似密码',
    'similarPasswordSubtitle': '密码包含标题或网站名',
    'healthDetailSimilar': '包含标题或网站名',
    'neverUpdated': '从未更新',
    'neverUpdatedSubtitle': '创建后从未修改过密码',
    'healthDetailNeverEdited': '创建后从未修改',
    'changePassword': '修改密码',
    'vaultHealthy': '密码库很健康',
    'noSecurityRisks': '没有发现安全风险',
    'analysisFailed': '分析失败，请重试',
    'renameTag': '重命名标签',
    'newTagName': '新标签名',
    'renameFailed': '重命名失败',
    'deleteTag': '删除标签',
    'deleteTagMessagePrefix': '将从所有条目中移除',
    'deleteTagMessageSuffix': '标签',
    'deleteFailed': '删除失败',
    'emptyTags': '暂无标签',
    'trashLoadFailed': '暂时无法读取回收站，请重试。',
    'permanentDeleteMessagePrefix': '确定要永久删除「',
    'permanentDeleteMessageSuffix': '」吗？此操作不可撤销。',
    'emptyTrashMessagePrefix': '确定要永久删除回收站中的',
    'emptyTrashMessageSuffix': '条记录吗？此操作不可撤销。',
    'justNow': '刚刚',
    'minutesAgo': '分钟前',
    'hoursAgo': '小时前',
    'daysAgo': '天前',
    'monthsAgo': '个月前',
    'yearsAgo': '年前',
    'restoreFailed': '恢复失败，请重试。',
    'permanentDelete': '永久删除',
    'emptyTrash': '清空回收站',
    'clearTrash': '清空',
    'clearTrashFailed': '清空失败，请重试。',
    'trashEmpty': '回收站为空',
    'trashEmptyMessage': '删除的密码记录会出现在这里。',
    'deletedRecords': '已删除记录',
    'healthScore': '密码健康分',
    'totalRecordsPrefix': '共',
    'totalRecordsSuffix': '条记录',
    'missingUsernameTrash': '未填写用户名',
    'vaultItemMissing': '这条记录不存在或已删除。',
    'vaultDetailLoadFailed': '暂时无法读取详情，请重试。',
    'deleteRecord': '删除记录',
    'deleteRecordMessage': '删除后此条记录将无法在列表中显示。确认删除？',
    'confirmDelete': '确认删除',
    'deleteRecordFailed': '删除失败，请稍后重试。',
    'passwordDetail': '密码详情',
    'exportPassword': '导出此密码',
    'detailUnavailable': '无法显示详情',
    'titleField': '标题',
    'websiteHint': 'https://example.com',
    'websiteField': '网址',
    'usernameField': '用户名',
    'passwordField': '密码',
    'notesField': '备注',
    'tagsField': '标签',
    'listSeparator': '、',
    'notFilled': '未填写',
    'hidden': '已隐藏',
    'usernameCopied': '用户名已复制。',
    'copyUsername': '复制用户名',
    'passwordHistory': '密码历史',
    'restorePassword': '恢复密码',
    'restorePasswordMessage': '将当前密码归档到历史记录，并用此密码替换。确认恢复？',
    'passwordRestored': '密码已恢复',
    'restorePasswordFailed': '恢复失败',
    'confirmRestore': '确认恢复',
    'singleBackupCopied': '单条加密备份已复制，30 秒后将自动清理剪贴板。',
    'exportSinglePassword': '导出单个密码',
    'exportSinglePasswordSubtitle':
        '导出内容已加密，仅包含当前记录。导入时需要此备份对应的主密码，导入后会使用本地密钥重新加密保存。',
    'addAttachment': '添加附件',
    'openAttachment': '打开附件',
    'deleteAttachment': '删除附件',
    'deleteAttachmentMessage': '删除附件“{name}”？此操作不可撤销。',
    'attachmentOpenFailed': '附件打开失败',
    'attachmentDeleteFailed': '附件删除失败',
    'attachmentAddFailed': '附件添加失败',
    'noAttachments': '没有附件',
    'displayNameRequired': '请输入显示名称',
    'contentRequired': '请输入内容',
    'displayName': '显示名称',
    'mediaType': '媒体类型',
    'content': '内容',
    'size': '大小',
    'editPassword': '编辑密码',
    'addPassword': '新增密码',
    'vaultEditLoadFailed': '暂时无法加载记录，请重试。',
    'saveFailed': '保存失败，请稍后重试。',
    'editUnavailable': '无法编辑',
    'titleHint': '例如：公司邮箱',
    'usernameHint': '用户名或邮箱',
    'passwordHint': '输入或生成密码',
    'enterTitle': '请输入标题',
    'enterPassword': '请输入密码',
    'totpTwoFactor': 'TOTP 二次验证',
    'scanQrCode': '扫描 QR 码',
    'manualInput': '手动输入',
    'totpConfigured': 'TOTP 已设置',
    'totpPageTitle': '认证器验证码',
    'totpPageSubtitle': '使用密码库关联的验证码，也可以添加独立 MFA 账号。',
    'totpHeaderVaultLinked': '{count} 个关联',
    'totpHeaderStandalone': '{count} 个独立',
    'totpHeaderTotal': '共 {count} 个',
    'totpEmptyTitle': '还没有认证器验证码',
    'totpEmptyMessage': '扫描设置二维码，或手动输入密钥来保护独立 MFA 账号。',
    'totpStandaloneLabel': '独立 MFA',
    'totpVaultLinkedLabel': '密码库关联',
    'totpManualTitle': '添加独立 MFA',
    'totpEditStandaloneTitle': '编辑独立 MFA',
    'totpDeleteStandaloneTitle': '删除独立 MFA',
    'totpDeleteStandaloneMessage': '要从认证器验证码中删除“{title}”吗？',
    'totpStandaloneDefaultTitle': '独立 MFA',
    'totpStandaloneNameLabel': '显示名称',
    'totpStandaloneNameHint': '例如：GitHub MFA',
    'totpStandaloneAccountLabel': '账号',
    'totpStandaloneAccountHint': 'name@example.com',
    'totpStandaloneSecretLabel': '密钥或 otpauth URL',
    'totpSecretInvalid': '请输入有效的 Base32 或 otpauth 密钥',
    'totpSaveStandalone': '保存 MFA',
    'totpSaveFailed': '无法保存此 MFA 条目，请重试。',
    'totpScanTitle': '扫描 MFA 设置',
    'totpScanSubtitle': '扫描认证器二维码。密钥只会保存在加密密码库中。',
    'totpScannerUnavailable': '当前环境不可用扫描器，请在下方粘贴 otpauth URL。',
    'totpPasteOtpAuthLabel': 'otpauth URL 或密钥',
    'totpPasteOtpAuthHint': 'otpauth://totp/...',
    'totpUsePastedOtpAuth': '使用粘贴内容',
    'addNotesHint': '添加备注信息...',
    'tagsHint': '选择或创建标签',
    'advancedInfo': '高级信息',
    'advancedInfoSubtitle': '可选的通行密钥信息，普通密码可不填',
    'enterTotpSecret': '输入 TOTP 密钥',
    'totpSecretHint': '粘贴 Base32 密钥',
    'totpSecretHelper': '例如：JBSWY3DPEHPK3PXP',
    'totpSecretEditHelper': '留空则保留当前已加密密钥。',
    'cameraPermissionRequired': 'QR 码扫描功能需要相机权限',
    'passkeyMetadata': '通行密钥信息（可选）',
    'passkeyRemoveConfirmTitle': '移除通行密钥信息？',
    'passkeyRemoveConfirmMessage': '这只会移除此条本地记录中保存的通行密钥准备信息。',
    'addPasskeyMetadata': '添加通行密钥信息',
    'editMetadata': '编辑信息',
    'relyingPartyId': '网站域名 ID',
    'rpId': '网站域名',
    'credential': '凭据',
    'user': '用户',
    'display': '显示名称',
    'algorithm': '算法',
    'readiness': '就绪状态',
    'exampleDomain': 'example.com',
    'credentialId': '凭据 ID',
    'credentialIdHint': 'base64url 格式的凭据 ID',
    'userHandle': '用户句柄',
    'publicKeyAlgorithm': '公钥算法',
    'algorithmHint': 'ES256',
    'platform': '平台',
    'platformHint': '例如：android',
    'platformApiReady': '平台 API 已就绪',
    'platformApiNotEnabled': '平台 API 未启用',
    'passwordStrength': '密码强度',
    'passwordStrengthWeak': '弱',
    'passwordStrengthFair': '中',
    'passwordStrengthStrongShort': '强',
    'generatorInvalidLength': '密码长度必须大于 0',
    'generatorNoCharacterClass': '请至少选择一种字符类型',
    'generatorLengthTooShort': '当前长度不足以覆盖已选字符类型',
    'generatorFailed': '无法生成密码，请检查生成规则。',
    'requiredField': '必填',
    'policyMinLength': '主密码至少需要 12 个字符',
    'policyCommonWeak': '主密码不能是常见弱密码',
    'policyRepeated': '主密码不能由重复字符组成',
    'policyKeyboardWalk': '主密码不能是键盘序列',
    'policyUseLongerPassphrase': '请使用更长的密码短语，或混合大小写、数字和符号',
    'policyStrongPassphrase': '强：密码短语更容易记忆且更难猜',
    'policyStrongMixed': '强：长度和字符组合较好',
    'policyFairImprove': '中：建议继续增强主密码',
    'policyEntryEmpty': '密码不能为空',
    'policyEntryMinLength': '建议至少 8 个字符',
    'policyEntryCommonWeak': '密码过于常见或容易猜测',
    'policyEntryStrong': '强：适合作为保存的条目密码',
    'policyEntryFair': '中：可用，但建议继续增强',
    'policyEntryWeak': '弱：建议生成更强密码',
    'copiedLocally': '已复制到本机剪贴板',
    'copyUnavailable': '复制不可用',
    'localCheckNotRunDetail': '运行一次明确的本机检查后，再解密已保存条目用于分析。',
    'localCheckFailedDetail': '密码库仍保留在本机；请确认已解锁后重试。',
    'healthScoreSuffix': '健康分',
    'savedItemsCheckedLocally': '条保存的记录已在本机检查。',
    'weakCountLabel': '弱密码',
    'reusedCountLabel': '重复',
    'staleCountLabel': '过期',
    'foundLocallySuffix': '项风险在本机发现。',
    'revokedStatus': '已撤销',
    'roadmapMigrationDetail': '导入向导和导出检查。',
    'roadmapAutofillDetail': '系统自动填充状态和设置状态。',
    'roadmapAttachmentsDetail': '加密文件存储就绪状态。',
    'roadmapPasskeysDetail': '通行密钥密码库支持入口。',
  };

  @override
  String text(String key) =>
      _text[key] ?? (throw ArgumentError.value(key, 'key', 'Unknown text key'));

  @override
  String get appName => 'Lockly';
  @override
  String get privacyCoverMessage => '隐私保护中...';
  @override
  String get vaultTab => '密码库';
  @override
  String get securityTab => '安全';
  @override
  String get totpTab => 'TOTP';
  @override
  String get generatorTab => '生成器';
  @override
  String get settingsTab => '设置';
  @override
  String get settingsTitle => '设置';
  @override
  String get languageTitle => '语言';
  @override
  String get languageSubtitle => '切换 Lockly 界面显示语言。';
  @override
  String get themeTitle => '主题';
  @override
  String get themeSubtitle => '选择浅色、深色或跟随系统主题。';
  @override
  String get themeLight => '浅色';
  @override
  String get themeDark => '深色';
  @override
  String get themeSystem => '跟随系统';
  @override
  String get vaultTitle => '密码库';
  @override
  String get securitySummaryTitle => '本地密码库';
  @override
  String get securitySummaryLoading => '正在校验本地加密记录';
  @override
  String vaultLocalRecordCount(int count) => '$count 条记录仅保存在本机';
  @override
  String get encryptedStatus => '已加密';
  @override
  String get localFirstStatus => '本地优先';
  @override
  String get searchLabel => '搜索';
  @override
  String get searchHint => '搜索记录';
  @override
  String searchResultCount(int count) => '搜索结果 $count 条';
  @override
  String get recentItemsTitle => '最近使用';
  @override
  String get allTagsFilter => '全部';
  @override
  String get addPasswordTooltip => '新增密码';
  @override
  String get vaultLoadFailedTitle => '读取失败';
  @override
  String get vaultLoadFailedMessage => '暂时无法读取密码列表，请重试。';
  @override
  String get retry => '重试';
  @override
  String get noSearchResultsTitle => '没有匹配结果';
  @override
  String get noSearchResultsMessage => '试试缩短关键词。';
  @override
  String get emptyVaultTitle => '还没有保存的密码';
  @override
  String get emptyVaultMessage => '点击右下角按钮新增第一条记录。';
  @override
  String trashTitleWithCount(int count) => '回收站 ($count 条)';
  @override
  String get missingUsername => '未填写用户名';
  @override
  String get passwordGeneratorTitle => '密码生成器';
  @override
  String get generatorRulesTitle => '生成规则';
  @override
  String get generatorRulesSubtitle => '默认保证每类已选字符至少出现一次。';
  @override
  String get generatorLengthLabel => '长度';
  @override
  String get generatorLowercase => '小写字母';
  @override
  String get generatorUppercase => '大写字母';
  @override
  String get generatorNumbers => '数字';
  @override
  String get generatorSymbols => '特殊符号';
  @override
  String get generatorExcludeConfusing => '排除易混字符';
  @override
  String get generatorRequireEveryClass => '每类至少一个';
  @override
  String get generatorResult => '生成结果';
  @override
  String get generatorEmptyHint => '点击生成后，可直接保存到新增密码页面。';
  @override
  String get generatorStrengthStrong => '强';
  @override
  String get generatePassword => '生成密码';
  @override
  String get regeneratePassword => '重新生成';
  @override
  String get saveThisPassword => '保存此密码';
  @override
  String get copyPasswordTooltip => '复制密码';
  @override
  String get passwordCopied => '密码已复制，30 秒后将自动清理剪贴板。';
  @override
  String get copyFailed => '复制失败，请重试。';
  @override
  String get unlockSecurityTitle => '解锁安全';
  @override
  String get unlockSecuritySubtitle => '管理主密码和生物识别快速解锁。';
  @override
  String get changeMasterPassword => '修改主密码';
  @override
  String get changeMasterPasswordSubtitle => '只重新加密 DEK，不重新加密所有条目。';
  @override
  String get biometricTitle => '生物识别';
  @override
  String get biometricSubtitle => '失败时仍需回退到主密码。';
  @override
  String get privacyProtectionTitle => '隐私保护';
  @override
  String get privacyProtectionSubtitle => '控制自动锁定和剪贴板清理时间。';
  @override
  String get autoLockTitle => '自动锁定';
  @override
  String get clipboardCleanupTitle => '剪贴板清理';
  @override
  String durationLabel(Duration value) {
    if (value.inMinutes >= 1) {
      return '${value.inMinutes} 分钟';
    }
    return '${value.inSeconds} 秒';
  }
}
