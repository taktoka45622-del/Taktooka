import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CaptureResult {
  final XFile file;
  final Map<String, dynamic> checks;
  const CaptureResult(this.file, this.checks);
}

Future<bool> validPersonalPhoto(XFile file) async =>
    throw UnsupportedError('Face verification requires the mobile app');

class CapturePage extends StatelessWidget {
  final String title;
  final bool face;
  const CapturePage({super.key, required this.title, this.face = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(child: Text('اختر صورة المستمسك من صفحة التسجيل')),
  );
}
