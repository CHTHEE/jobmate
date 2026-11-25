import 'package:flutter/material.dart';

/// Keeps the toolbar visible while revealing the page's independent filters.
/// Criteria live in the parent so closing the panel never clears a selection.
class ExpandableFilterBar extends StatefulWidget {
  const ExpandableFilterBar({
    super.key,
    this.search,
    required this.filters,
    this.activeCount = 0,
    this.onClear,
  });

  final Widget? search;
  final List<Widget> filters;
  final int activeCount;
  final VoidCallback? onClear;

  @override
  State<ExpandableFilterBar> createState() => _ExpandableFilterBarState();
}

class _ExpandableFilterBarState extends State<ExpandableFilterBar>
    with AutomaticKeepAliveClientMixin<ExpandableFilterBar> {
  bool _expanded = false;

  @override
  bool get wantKeepAlive => _expanded;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final count = widget.activeCount;
    final label = count == 0 ? 'Filters' : 'Filters ($count)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            void toggle() {
              setState(() => _expanded = !_expanded);
              updateKeepAlive();
            }

            final compact =
                widget.search != null &&
                constraints.maxWidth <
                    420 * MediaQuery.textScalerOf(context).scale(14) / 14;
            final icon = Icon(_expanded ? Icons.expand_less : Icons.tune);
            final button = Semantics(
              expanded: _expanded,
              child: compact
                  ? IconButton.outlined(
                      key: const ValueKey('workspace-filters-toggle'),
                      tooltip: label,
                      onPressed: toggle,
                      icon: count == 0
                          ? icon
                          : Badge(label: Text('$count'), child: icon),
                    )
                  : OutlinedButton.icon(
                      key: const ValueKey('workspace-filters-toggle'),
                      onPressed: toggle,
                      label: Text(label),
                      icon: icon,
                    ),
            );
            return Row(
              children: [
                if (widget.search case final search?) ...[
                  Expanded(child: search),
                  const SizedBox(width: 8),
                ],
                button,
              ],
            );
          },
        ),
        AnimatedSize(
          alignment: Alignment.topLeft,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: Offstage(
            offstage: !_expanded,
            child: ExcludeFocus(
              excluding: !_expanded,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...widget.filters,
                      if (widget.onClear != null)
                        TextButton(
                          onPressed: widget.onClear,
                          child: const Text('Clear filters'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
