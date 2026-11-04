import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'workspace_destinations.dart';

/// Keep pushed detail URLs in browser history as well as root `go` navigation.
void configureAppNavigation() {
  GoRouter.optionURLReflectsImperativeAPIs = kIsWeb;
}

/// Web destinations behave like browser pages without animating the entire
/// workspace chrome. Native tab roots also switch without moving the bottom
/// bar; focused/detail routes keep Material's platform-aware transition.
Page<void> appPage(GoRouterState state, Widget child) {
  if (kIsWeb || isWorkspaceRootPath(state.uri.path)) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }
  return MaterialPage<void>(key: state.pageKey, child: child);
}
