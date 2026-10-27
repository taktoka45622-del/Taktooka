import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/design.dart';

class ProfilePhoto extends StatefulWidget {
  final String? path;
  final double size;
  const ProfilePhoto({super.key, this.path, this.size = 56});
  @override
  State<ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends State<ProfilePhoto> {
  Future<String>? image;
  Timer? refresh;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(ProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) load();
  }

  @override
  void dispose() {
    refresh?.cancel();
    super.dispose();
  }

  void load() {
    refresh?.cancel();
    final path = widget.path;
    image = path == null || path.isEmpty
        ? null
        : Supabase.instance.client.storage
              .from('profile-photos')
              .createSignedUrl(path, 1800);
    if (image != null)
      refresh = Timer(const Duration(minutes: 25), () {
        if (mounted) setState(load);
      });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = CategoryIcon(
      Icons.person_outline,
      circle: true,
      size: widget.size,
      color: muted,
      background: const Color(0xfff0f0f0),
    );
    if (image == null) return fallback;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: FutureBuilder<String>(
          future: image,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return fallback;
            return Image.network(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => fallback,
            );
          },
        ),
      ),
    );
  }
}
