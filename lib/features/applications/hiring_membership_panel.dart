import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';
import 'hiring_membership_status.dart';

/// Read-only hired membership state. Retry only re-reads; never accepts/re-enrolls.
class HiringMembershipPanel extends StatefulWidget {
  const HiringMembershipPanel({
    super.key,
    required this.source,
    required this.applicationId,
  });
  final HiringMembershipStatusSource source;
  final String applicationId;

  @override
  State<HiringMembershipPanel> createState() => _HiringMembershipPanelState();
}

class _HiringMembershipPanelState extends State<HiringMembershipPanel> {
  late Future<HiringMembershipSnapshot> result;

  Future<HiringMembershipSnapshot> read() async =>
      widget.source.loadMembership(widget.applicationId);

  @override
  void initState() {
    super.initState();
    result = read();
  }

  @override
  void didUpdateWidget(covariant HiringMembershipPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.applicationId != widget.applicationId) {
      result = read();
    }
  }

  @override
  Widget build(BuildContext context) => WorkspaceCard(
    title: 'Company membership',
    child: FutureBuilder<HiringMembershipSnapshot>(
      future: result,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final data = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading) ...[
              const LinearProgressIndicator(),
              const Text('Checking company membership…'),
            ] else if (snapshot.hasError || data == null) ...[
              const Text('Company membership could not be confirmed.'),
              const Text(
                'Retry this check. Do not accept the offer again just because this check failed.',
              ),
            ] else ...[
              Text(switch (data.state) {
                HiringMembershipState.active => 'Membership: Active',
                HiringMembershipState.inactive => 'Membership: Inactive',
                HiringMembershipState.revoked => 'Membership: Revoked',
                HiringMembershipState.notRecorded => 'Membership: Not recorded',
              }),
              if (data.role == 'member')
                const Text(
                  'Ordinary member. This does not grant management permissions.',
                ),
              if (!data.acceptanceRecorded ||
                  data.state == HiringMembershipState.notRecorded)
                const Text(
                  'The hiring membership link needs company review. Refresh to check again.',
                ),
              if (data.state == HiringMembershipState.inactive ||
                  data.state == HiringMembershipState.revoked)
                const Text(
                  'Contact the company for review. Refreshing will not reactivate membership.',
                ),
              const Text(
                'Work shifts and application history are managed separately.',
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: loading
                  ? null
                  : () => setState(() {
                      result = read();
                    }),
              child: Text(
                snapshot.hasError
                    ? 'Retry membership check'
                    : 'Refresh membership',
              ),
            ),
          ],
        );
      },
    ),
  );
}
