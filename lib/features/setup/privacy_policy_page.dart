import 'package:flutter/material.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私政策'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SecureVisualBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用户协议（本地密码库）',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '欢迎使用"本地密码库"应用（以下简称"本应用"）。在使用本应用前，请仔细阅读以下协议条款，确保您充分理解并同意所有内容后再使用本应用。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '1. 服务内容',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本应用为本地密码管理工具，主要功能包括：\n\n密码记录、生成、分类管理\n本地数据加密存储\n密码强度评估及安全提示',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '2. 数据存储与安全',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本应用不在任何服务器上存储用户密码或敏感信息，所有数据仅保存在用户设备本地。\n用户数据通过端到端加密技术保护，保证数据在本机安全。\n密码本地删除操作一旦执行不可恢复，请用户谨慎操作。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '3. 用户义务',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '用户须妥善保管主密码及设备，避免他人获取访问权限。\n遵守当地法律法规，确保不利用本应用进行非法活动。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '4. 免责条款',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本应用对因用户操作不当（如密码遗忘或误删）造成的任何数据丢失不承担责任。\n本应用在合理范围内保障功能正常，但不保证在所有设备及环境下完全无故障。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '5. 协议修改',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本应用有权在必要时更新用户协议，更新内容将通过应用内提示通知用户。\n用户继续使用应用即视为接受更新后的协议。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              Text(
                '隐私政策（本地密码库）',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '本应用重视用户隐私与数据安全，请仔细阅读以下内容：',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '1. 数据收集',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本应用不收集任何个人信息或账号信息。\n所有用户数据（包括密码、标签、备注等）均存储在本地设备。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '2. 数据使用',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '用户数据仅用于本地密码管理、密码生成及安全评估。\n本应用不会将数据上传云端或共享给第三方。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '3. 数据安全',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '用户密码和敏感信息通过本地加密方式保护。\n删除本地数据或卸载应用将永久删除所有记录，不可恢复。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '4. 第三方服务',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本应用不依赖第三方服务器处理用户数据。\n如果集成第三方功能（如图标或字体包），不会涉及用户敏感信息。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '5. 用户权利',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '用户可随时查看、修改或删除本地数据。\n用户可选择退出应用或卸载应用，所有本地数据将随之删除。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                '6. 政策更新',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本隐私政策可能随应用版本更新而调整。\n用户继续使用应用即表示同意更新后的隐私政策。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}