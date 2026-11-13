import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_page.dart';
import '../applications/module2_widgets.dart';
import 'chat_page.dart';

GoRoute chatRoute(String path, {bool employer = false}) {
  final guards = <LocalKey, Future<bool> Function()>{};
  return GoRoute(
    path: path,
    onExit: (_, state) async => await guards[state.pageKey]?.call() ?? true,
    pageBuilder: (_, state) => appPage(
      state,
      _ChatRouteBody(
        key: ValueKey(state.pageKey),
        routeKey: state.pageKey,
        guards: guards,
        employer: employer,
        conversationId: state.pathParameters['conversationId'],
      ),
    ),
  );
}

class _ChatRouteBody extends StatefulWidget {
  const _ChatRouteBody({
    super.key,
    required this.routeKey,
    required this.guards,
    required this.employer,
    this.conversationId,
  });
  final LocalKey routeKey;
  final Map<LocalKey, Future<bool> Function()> guards;
  final bool employer;
  final String? conversationId;
  @override
  State<_ChatRouteBody> createState() => _ChatRouteBodyState();
}

class _ChatRouteBodyState extends State<_ChatRouteBody> {
  final _page = GlobalKey<ChatPageState>();
  Future<bool> _exit() async => await _page.currentState?.confirmExit() ?? true;
  @override
  void initState() {
    super.initState();
    widget.guards[widget.routeKey] = _exit;
  }

  @override
  void dispose() {
    widget.guards.remove(widget.routeKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Module2Gate(
    role: widget.employer ? 'employer' : 'job_seeker',
    child: ChatPage(
      key: _page,
      employer: widget.employer,
      conversationId: widget.conversationId,
    ),
  );
}
