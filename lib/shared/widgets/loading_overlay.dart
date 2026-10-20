import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Please wait...',
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isLoading,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (isLoading) ...[
            const ModalBarrier(color: Colors.black54, dismissible: false),
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(message),
                    ],
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
