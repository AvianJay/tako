import 'package:flutter/material.dart';

class ThinkingSection extends StatefulWidget {
  const ThinkingSection({
    required this.text,
    required this.label,
    required this.hasAnswer,
    super.key,
  });
  final String text;
  final String label;
  final bool hasAnswer;
  @override
  State<ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<ThinkingSection> {
  bool _expanded = false;
  @override
  void didUpdateWidget(covariant ThinkingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.hasAnswer && widget.hasAnswer) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_outlined, size: 15),
                    const SizedBox(width: 7),
                    Text(
                      widget.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 5),
                    AnimatedRotation(
                      turns: _expanded ? .5 : 0,
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more, size: 17),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            alignment: Alignment.topLeft,
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    child: SelectableText(
                      widget.text,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
