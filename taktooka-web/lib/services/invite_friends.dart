import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taktooka/core/gender_copy.dart';

const appDownloadUrl = String.fromEnvironment(
  'APP_DOWNLOAD_URL',
  defaultValue: '',
);
Future<void> inviteFriends(BuildContext context) async {
  final message =
      'جرّب تكتوكة 🛺 مشوارك أسهل!' +
      (appDownloadUrl.isEmpty ? '' : '\n$appDownloadUrl');
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: AppText(
              'دعوة أصدقائك',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const AppText('نسخ رسالة الدعوة'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: AppText('تم نسخ رسالة الدعوة')),
                );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const AppText('مشاركة عبر واتساب'),
            onTap: () async {
              final opened = await launchUrl(
                Uri.https('wa.me', '/', {'text': message}),
                mode: LaunchMode.externalApplication,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (!opened && context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: AppText(
                      'تعذر فتح واتساب؛ استخدم نسخ رسالة الدعوة',
                    ),
                  ),
                );
            },
          ),
        ],
      ),
    ),
  );
}
