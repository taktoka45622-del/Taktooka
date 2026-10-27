import 'package:taktooka/core/gender_copy.dart';
import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';

class RideDetailsPanel extends StatefulWidget {
  final String rideId;
  final double maxHeight;
  final Widget child;
  final Widget? footer;

  const RideDetailsPanel({
    super.key,
    required this.rideId,
    required this.maxHeight,
    required this.child,
    this.footer,
  });

  @override
  State<RideDetailsPanel> createState() => _RideDetailsPanelState();
}

class _RideDetailsPanelState extends State<RideDetailsPanel> {
  bool _visible = true;

  @override
  void didUpdateWidget(covariant RideDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rideId != widget.rideId) _visible = true;
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16)],
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                  ),
                  label: AppText(_visible ? 'إخفاء التفاصيل' : 'عرض التفاصيل'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scarlet,
                    minimumSize: const Size(double.infinity, 48),
                    side: BorderSide(color: scarlet.withValues(alpha: .2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (_visible)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: widget.child,
                  ),
                ),
              if (widget.footer != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: widget.footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
