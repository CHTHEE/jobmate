import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import 'chat_dependencies.dart';
import 'chat_repository.dart';

/// Lazy creation only on a deliberate participant action.
class ChatApplicationButton extends StatefulWidget {
  const ChatApplicationButton({
    super.key,
    required this.applicationId,
    this.employer = false,
    this.enabled = true,
    this.createRepository,
  });
  final String applicationId;
  final bool employer, enabled;
  final ChatRepository Function()? createRepository;
  @override
  State<ChatApplicationButton> createState() => _ChatApplicationButtonState();
}

class _ChatApplicationButtonState extends State<ChatApplicationButton> {
  bool _busy = false;
  String? _error;
  Future<void> _open() async {
    if (_busy || !widget.enabled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final application = widget.applicationId;
    ChatRepository? repo;
    try {
      repo = (widget.createRepository ?? authenticatedChatRepository)();
      final actor = repo.source.userId;
      final id = await repo.getOrCreate(application);
      if (!mounted || widget.applicationId != application) return;
      if (repo.source.userId != actor) throw const ChatSessionChanged();
      final root = widget.employer
          ? AppRoutes.employerMessages
          : AppRoutes.messages;
      await context.push<void>('$root/$id');
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = chatError(error);
        });
      }
    } finally {
      repo?.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: widget.enabled && !_busy ? _open : null,
        icon: const Icon(Icons.chat_bubble_outline),
        label: Text(
          _busy
              ? 'Opening conversation…'
              : widget.employer
              ? 'Message Applicant'
              : 'Message Employer',
        ),
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
