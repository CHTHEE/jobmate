import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dispute_gateway.dart';
import 'dispute_page.dart';
import 'dispute_submission_context.dart';
import 'dispute_submit_dialog.dart';

class DisputeContextAction extends StatelessWidget {
  const DisputeContextAction({
    super.key,
    required this.contextData,
    required this.role,
    this.enabled = true,
    this.gateway,
    this.onSubmitted,
  });

  final DisputeSubmissionContext contextData;
  final String role;
  final bool enabled;
  final DisputeGateway? gateway;
  final Future<void> Function()? onSubmitted;

  Future<void> _report(BuildContext context) async {
    final activeGateway =
        gateway ?? SupabaseDisputeGateway(Supabase.instance.client);
    final id = await showDisputeSubmitDialog(
      context,
      gateway: activeGateway,
      submissionContext: contextData,
    );
    if (!context.mounted || id == null) return;
    await onSubmitted?.call();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Dispute submitted successfully.'),
        action: SnackBarAction(
          label: 'View dispute',
          onPressed: () => showDisputeDetailsModal(
            context,
            disputeId: id,
            gateway: activeGateway,
            role: role,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'More actions',
    enabled: enabled,
    onSelected: (_) => _report(context),
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: 'report',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.flag_outlined),
          title: Text('Report a dispute'),
        ),
      ),
    ],
  );
}
