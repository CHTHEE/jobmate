import 'package:flutter/material.dart';

import 'responsive_layout.dart';

class AppStartupException implements Exception {
  const AppStartupException(this.message);
  final String message;
}

/// Draw a first frame before asynchronous configuration and SDK initialization.
class AppStartup extends StatefulWidget {
  const AppStartup({
    super.key,
    required this.initialize,
    required this.builder,
  });
  final Future<void> Function() initialize;
  final WidgetBuilder builder;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = Future<void>.sync(widget.initialize);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return widget.builder(context);
      }
      final error = snapshot.error;
      return MaterialApp(
        title: 'JobMate',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D9488)),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ResponsiveContent(
                  maxWidth: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.work_outline,
                        color: Color(0xFF0D9488),
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'JobMate',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!snapshot.hasError) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('Starting JobMate…'),
                      ] else ...[
                        const Text(
                          'JobMate could not start',
                          style: TextStyle(fontSize: 20),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          error is AppStartupException ? error.message : 'Initialization failed. Retry, or restart the app if the problem continues.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () {
                            final initialization = Future<void>.sync(
                              widget.initialize,
                            );
                            setState(() {
                              _initialization = initialization;
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
