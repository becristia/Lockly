import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';

String localizedMasterPasswordPolicyMessage(
  MasterPasswordPolicyResult result,
  AppStrings strings,
) {
  return switch (result.messageCode) {
    PasswordPolicyMessageCode.masterMinLength => strings.text(
      'policyMinLength',
    ),
    PasswordPolicyMessageCode.masterCommonWeak => strings.text(
      'policyCommonWeak',
    ),
    PasswordPolicyMessageCode.masterRepeated => strings.text('policyRepeated'),
    PasswordPolicyMessageCode.masterKeyboardWalk => strings.text(
      'policyKeyboardWalk',
    ),
    PasswordPolicyMessageCode.masterUseLongerPassphrase => strings.text(
      'policyUseLongerPassphrase',
    ),
    PasswordPolicyMessageCode.masterStrongPassphrase => strings.text(
      'policyStrongPassphrase',
    ),
    PasswordPolicyMessageCode.masterStrongMixed => strings.text(
      'policyStrongMixed',
    ),
    PasswordPolicyMessageCode.masterFairImprove => strings.text(
      'policyFairImprove',
    ),
    PasswordPolicyMessageCode.entryEmpty => strings.text('policyEntryEmpty'),
    PasswordPolicyMessageCode.entryMinLength => strings.text(
      'policyEntryMinLength',
    ),
    PasswordPolicyMessageCode.entryCommonWeak => strings.text(
      'policyEntryCommonWeak',
    ),
    PasswordPolicyMessageCode.entryStrong => strings.text('policyEntryStrong'),
    PasswordPolicyMessageCode.entryFair => strings.text('policyEntryFair'),
    PasswordPolicyMessageCode.entryWeak => strings.text('policyEntryWeak'),
  };
}
