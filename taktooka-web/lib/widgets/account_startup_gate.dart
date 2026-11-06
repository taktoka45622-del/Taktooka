import 'package:flutter/material.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'brand_title.dart';
import 'skeleton.dart';

class AccountStartupGate extends StatelessWidget {
  final bool ready;
  final String? error;
  final bool syncing;
  final VoidCallback retry, signOut;
  final WidgetBuilder builder;
  const AccountStartupGate({
    super.key,
    required this.ready,
    this.error,
    this.syncing = false,
    required this.retry,
    required this.signOut,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) {
    if (ready) return builder(context);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const BrandTitle()),
      body: error == null
          ? const SkeletonPage()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppText(error!),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: syncing ? null : retry,
                      child: const AppText('إعادة المحاولة'),
                    ),
                    TextButton(
                      onPressed: signOut,
                      child: const AppText('تسجيل خروج'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
