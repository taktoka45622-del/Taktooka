import 'skeleton.dart';
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
  static final Map<String, (DateTime, Future<String>)> signed = {};
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
    if (path == null || path.isEmpty) {
      image = null;
    } else {
      final client = Supabase.instance.client;
      final key = '${client.auth.currentUser?.id}:$path';
      final saved = signed[key];
      if (saved != null && DateTime.now().difference(saved.$1).inMinutes < 24) {
        image = saved.$2;
      } else {
        final request = client.storage
            .from('profile-photos')
            .createSignedUrl(path, 1800);
        if (signed.length >= 100) signed.remove(signed.keys.first);
        signed[key] = (DateTime.now(), request);
        image = request;
        unawaited(
          request.then<void>(
            (_) {},
            onError: (Object _) {
              if (identical(signed[key]?.$2, request)) signed.remove(key);
            },
          ),
        );
      }
    }
    if (image != null) {
      final key = '${Supabase.instance.client.auth.currentUser?.id}:$path';
      final savedAt = signed[key]?.$1 ?? DateTime.now();
      final remaining =
          const Duration(minutes: 24) - DateTime.now().difference(savedAt);
      refresh = Timer(
        remaining.isNegative ? const Duration(seconds: 1) : remaining,
        () {
          if (mounted) setState(load);
        },
      );
    }
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
            if (snapshot.hasError) return fallback;
            if (!snapshot.hasData)
              return SkeletonShimmer(
                child: SkeletonBlock(
                  height: widget.size,
                  width: widget.size,
                  radius: widget.size / 2,
                ),
              );
            return Image.network(
              snapshot.data!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, synchronous) =>
                  synchronous || frame != null
                  ? child
                  : SkeletonShimmer(
                      child: SkeletonBlock(
                        height: widget.size,
                        width: widget.size,
                        radius: widget.size / 2,
                      ),
                    ),
              errorBuilder: (_, error, stack) => fallback,
            );
          },
        ),
      ),
    );
  }
}
