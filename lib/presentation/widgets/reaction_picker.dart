import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../data/models/reaction_model.dart';

class ReactionPicker extends StatefulWidget {
  final Function(ReactionType) onReactionSelected;
  final VoidCallback? onDismiss;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
    this.onDismiss,
  });

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectReaction(ReactionType type) {
    widget.onReactionSelected(type);
    // Don't dismiss immediately - let parent handle it
    // This allows the picker to stay visible after selection
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReactionButton(
                type: ReactionType.like,
                onTap: () => _selectReaction(ReactionType.like),
              ),
              _ReactionButton(
                type: ReactionType.love,
                onTap: () => _selectReaction(ReactionType.love),
              ),
              _ReactionButton(
                type: ReactionType.care,
                onTap: () => _selectReaction(ReactionType.care),
              ),
              _ReactionButton(
                type: ReactionType.haha,
                onTap: () => _selectReaction(ReactionType.haha),
              ),
              _ReactionButton(
                type: ReactionType.wow,
                onTap: () => _selectReaction(ReactionType.wow),
              ),
              _ReactionButton(
                type: ReactionType.sad,
                onTap: () => _selectReaction(ReactionType.sad),
              ),
              _ReactionButton(
                type: ReactionType.angry,
                onTap: () => _selectReaction(ReactionType.angry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionButton extends StatefulWidget {
  final ReactionType type;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.type,
    required this.onTap,
  });

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        debugPrint('Reaction button tapped: ${widget.type}');

        // Trigger selection immediately (parent may dismiss this widget).
        widget.onTap();

        // Defensive: the picker may get disposed immediately after selection.
        try {
          await _controller.forward();
          if (!mounted) return;
          await _controller.reverse();
        } on TickerCanceled {
          // Animation got cancelled due to dispose; ignore.
        } catch (_) {
          // Never let an animation error crash the app.
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 1.3).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          ),
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Text(
              widget.type.emoji,
              style: const TextStyle(fontSize: 32),
            ),
          ),
        ),
      ),
    );
  }
}


