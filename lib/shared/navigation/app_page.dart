import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Web destinations behave like browser pages without animating the entire
/// workspace chrome. Native routes keep Material's platform-aware transition.
Page<void> appPage(GoRouterState state, Widget child) {
  if (kIsWeb) return NoTransitionPage<void>(key: state.pageKey, child: child);
  return MaterialPage<void>(key: state.pageKey, child: child);
}
