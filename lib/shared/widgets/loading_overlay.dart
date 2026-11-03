import 'package:flutter/material.dart';

import 'responsive_layout.dart';

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final String? description;
  final String? note;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Please wait...',
    this.description,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isLoading,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: isLoading,
            child: ExcludeSemantics(
              excluding: isLoading,
              child: AbsorbPointer(absorbing: isLoading, child: child),
            ),
          ),
          if (isLoading) ...[
            const ModalBarrier(color: Colors.black54, dismissible: false),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: ResponsiveLayout.pagePadding(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SingleChildScrollView(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              if (description != null) ...[
                                const SizedBox(height: 12),
                                Text(description!, textAlign: TextAlign.center),
                              ],
                              if (note != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  note!,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
