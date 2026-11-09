import 'dart:ui';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/keys/keys.dart';
import 'package:flutter/material.dart';

String? _lastMessage;

enum MessageType { warning, complete, error, none }

// ---------------------------------------------------------------------------
// Public helpers – single entry point, zero duplication
// ---------------------------------------------------------------------------

void _showMessage(String aMessage, MessageType type) {
  if (_lastMessage == aMessage) return;
  _lastMessage = aMessage;
  Future.delayed(const Duration(seconds: 3), () {
    _lastMessage = null;
  });
  ToastService.show(aMessage, type: type);
}

void message(String aMessage) => _showMessage(aMessage, MessageType.none);

void messageError(String aMessage) => _showMessage(aMessage, MessageType.error);

void messageComplete(String aMessage) =>
    _showMessage(aMessage, MessageType.complete);

void messageWarning(String aMessage) =>
    _showMessage(aMessage, MessageType.warning);

// ---------------------------------------------------------------------------
// ToastService – overlay lifecycle
// ---------------------------------------------------------------------------

class ToastService {
  static OverlayEntry? _overlayEntry;

  static void show(
    String message, {
    Duration duration = const Duration(seconds: 3),
    MessageType type = MessageType.none,
  }) {
    final overlay = GlobalKeys.navigator.currentState?.overlay;
    if (overlay == null) return;

    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }

    _overlayEntry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        type: type,
        duration: duration,
        onRemove: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
        },
      ),
    );

    overlay.insert(_overlayEntry!);
  }
}

// ---------------------------------------------------------------------------
// Animated toast widget
// ---------------------------------------------------------------------------

class _ToastWidget extends StatefulWidget {
  final String message;
  final MessageType type;
  final Duration duration;
  final VoidCallback onRemove;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onRemove,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    Future.delayed(widget.duration, () {
      if (mounted) _dismiss();
    });
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    await _controller.reverse();
    if (mounted) widget.onRemove();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color tintColor;
    IconData icon;
    switch (widget.type) {
      case MessageType.error:
        tintColor = context.colors.danger;
        icon = Icons.error_rounded;
        break;
      case MessageType.warning:
        tintColor = context.colors.warning;
        icon = Icons.warning_rounded;
        break;
      case MessageType.complete:
        tintColor = context.colors.good;
        icon = Icons.check_circle_rounded;
        break;
      default:
        tintColor = context.colors.accent;
        icon = Icons.info_rounded;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: _slideAnimation,
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: GestureDetector(
                onTap: _dismiss,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLG),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? context.colors.surface.withAlpha(20)
                            : context.colors.surface.withAlpha(220),
                        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
                        border: Border.all(
                          color: isDark
                              ? context.colors.divider.withAlpha(30)
                              : context.colors.divider.withAlpha(200),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tintColor.withAlpha(isDark ? 25 : 15),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: context.colors.textPrimary.withAlpha(
                              isDark ? 40 : 10,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: tintColor.withAlpha(30),
                              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                            ),
                            child: Icon(icon, color: tintColor, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                color: context.colors.textPrimary.withAlpha(
                                  230,
                                ),
                                fontSize: 13,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: context.colors.textSecondary.withAlpha(160),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
