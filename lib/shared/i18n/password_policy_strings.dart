import 'package:secure_box/core/security/master_password_policy.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';

String localizedMasterPasswordPolicyMessage(
  MasterPasswordPolicyResult result,
  AppStrings strings,
) {
  return switch (result.message) {
    '主密码至少需要 12 个字符' => strings.text('policyMinLength'),
    '主密码不能是常见弱密码' => strings.text('policyCommonWeak'),
    '主密码不能由重复字符组成' => strings.text('policyRepeated'),
    '主密码不能是键盘序列' => strings.text('policyKeyboardWalk'),
    '请使用更长的密码短语，或混合大小写、数字和符号' =>
      strings.text('policyUseLongerPassphrase'),
    '强：密码短语更容易记忆且更难猜' =>
      strings.text('policyStrongPassphrase'),
    '强：长度和字符组合较好' => strings.text('policyStrongMixed'),
    '中：建议继续增强主密码' => strings.text('policyFairImprove'),
    _ => result.message,
  };
}
