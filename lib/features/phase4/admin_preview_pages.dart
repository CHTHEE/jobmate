import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import '../demo_work/local_attachment.dart';
import '../attendance/report_print.dart';
import '../jobs/job_display.dart';
import 'phase4_store.dart';

const adminPreviewDisclaimer =
    'Administrator UI sandbox: every account, vacancy, case, metric and action below is fictional. Real users, job posts and company verification are unchanged. Local audit entries are not secure or immutable server audit logs.';

class AdminPreviewGate extends StatefulWidget {
  const AdminPreviewGate({super.key, required this.child, this.checkAccess});
  final Widget child;
  final Future<bool> Function()? checkAccess;
  @override
  State<AdminPreviewGate> createState() => _AdminPreviewGateState();
}

class _AdminPreviewGateState extends State<AdminPreviewGate> {
  late Future<bool> access = load();
  Future<bool> load() async {
    if (widget.checkAccess != null) return widget.checkAccess!();
    final client = Supabase.instance.client,
        id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) return false;
    final account = await client
        .from('users')
        .select('role, status')
        .eq('user_id', id)
        .single();
    if (account['role'] != 'administrator' ||
        account['status'] != 'active' ||
        client.auth.currentUser?.id != id) {
      return false;
    }
    try {
      final result = await client.functions.invoke(
        'admin-invitations',
        body: {'action': 'check_access'},
      );
      return client.auth.currentUser?.id == id &&
          result.status == 200 &&
          result.data is Map &&
          result.data['isAdmin'] == true;
    } on FunctionException catch (error) {
      if ([401, 403].contains(error.status)) return false;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: access,
    builder: (context, snapshot) {
      if (snapshot.data == true) return widget.child;
      return Scaffold(
        appBar: const ResponsivePageAppBar(title: Text('Administrator access')),
        body: Center(
          child: SingleChildScrollView(
            padding: ResponsiveLayout.pagePadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (snapshot.connectionState != ConnectionState.done)
                  const CircularProgressIndicator()
                else
                  ModuleState(
                    title: snapshot.hasError
                        ? 'Unable to verify administrator access'
                        : 'Access denied',
                    message: 'An active administrator account and the existing server access check are required. No UI role switch can grant access.',
                    action: snapshot.hasError
                        ? () => setState(() {
                            access = load();
                          })
                        : null,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class AdminPreviewPage extends StatefulWidget {
  const AdminPreviewPage({super.key, this.section = 'Overview', this.store});
  final String section;
  final Phase4Store? store;
  @override
  State<AdminPreviewPage> createState() => _AdminPreviewPageState();
}

class _AdminPreviewPageState extends State<AdminPreviewPage> {
  late final store = widget.store ?? Phase4Store.session;
  final search = TextEditingController();
  String filter = '', roleFilter = '', period = 'All';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdminPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      filter = '';
      roleFilter = '';
      search.clear();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final section = widget.section,
          path = switch (widget.section) {
            'Accounts' => AppRoutes.adminDemoAccounts,
            'Jobs' => AppRoutes.adminDemoJobs,
            'Disputes' => AppRoutes.adminDemoDisputes,
            'Reports' => AppRoutes.adminDemoReports,
            _ => AppRoutes.adminPreview,
          };
      final cases = store.disputes
          .where(
            (d) =>
                (filter.isEmpty || d.state.label == filter) &&
                '${d.id} ${d.category} ${d.subject} ${d.reason}'
                    .toLowerCase()
                    .contains(search.text.toLowerCase().trim()),
          )
          .toList();
      final accounts = store.accounts
          .where(
            (a) =>
                (filter.isEmpty || a.state == filter) &&
                (roleFilter.isEmpty || a.role == roleFilter) &&
                '${a.name} ${a.id}'.toLowerCase().contains(
                  search.text.toLowerCase().trim(),
                ),
          )
          .toList();
      final jobs = store.jobs
          .where(
            (j) =>
                (filter.isEmpty || j.state == filter) &&
                '${j.title} ${j.company}'.toLowerCase().contains(
                  search.text.toLowerCase().trim(),
                ),
          )
          .toList();
      final reportCases = store.disputes
          .where(
            (d) =>
                period == 'All' ||
                DateTime.now().difference(d.timeline.first.$2).inDays <=
                    int.parse(period),
          )
          .toList();
      final metrics = {
        'Sample accounts': store.accounts.length,
        'Sample job posts': store.jobs.length,
        'Cases in selected period': reportCases.length,
        'Unresolved cases': reportCases.where((d) => !d.state.terminal).length,
        'Local audit entries': store.audit.length,
      };
      return DemoPage(
        title: 'Admin ${section == 'Overview' ? 'UI Sandbox' : section} (demo)',
        maxWidth: section == 'Reports' ? 768 : 896,
        path: path,
        role: 'administrator',
        children: [
          const Phase3Notice(adminPreviewDisclaimer),
          if (section == 'Overview') ...[
            DemoStats(metrics),
            WorkspaceCard(
              title: 'Existing real administration',
              subtitle: 'KZ’s existing dashboard, directory, company review and permission flows remain authoritative.',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: const Text('Real Admin Dashboard'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push(AppRoutes.adminUsers),
                    child: const Text('Real User Directory'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final item in <(String, String)>[
              ('Demo Account Actions', AppRoutes.adminDemoAccounts),
              ('Demo Job Moderation', AppRoutes.adminDemoJobs),
              ('Demo Disputes', AppRoutes.adminDemoDisputes),
              ('Demo Reports', AppRoutes.adminDemoReports),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton(
                  onPressed: () => context.push(item.$2),
                  child: Text(item.$1),
                ),
              ),
          ] else if (section == 'Reports') ...[
            ModuleSelect(
              label: 'Sample case period',
              value: period,
              options: const {
                'All': 'All session cases',
                '7': 'Last 7 days',
                '30': 'Last 30 days',
              },
              onChanged: (v) => setState(() => period = v),
            ),
            const SizedBox(height: 20),
            DemoStats(metrics),
            WorkspaceCard(
              title: 'Case status distribution',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in DisputeState.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${s.label}: ${reportCases.where((d) => d.state == s).length}',
                          ),
                          LinearProgressIndicator(
                            value: reportCases.isEmpty
                                ? 0
                                : reportCases
                                          .where((d) => d.state == s)
                                          .length /
                                      reportCases.length,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            WorkspaceCard(
              title: 'Account standing summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in ['Active', 'Restricted', 'Suspended'])
                    WorkspaceInfo(
                      s,
                      '${store.accounts.where((a) => a.state == s).length} demo accounts',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: !kIsWeb
                  ? null
                  : () {
                      try {
                        if (!openReportPrint(adminReportHtml(metrics))) {
                          demoMessage(
                            context,
                            'Print window blocked; allow popups and retry.',
                          );
                        }
                      } catch (_) {
                        demoMessage(
                          context,
                          'Print view unavailable. Retry in a Web browser.',
                        );
                      }
                    },
              icon: const Icon(Icons.print_outlined),
              label: Text(
                kIsWeb
                    ? 'Open Printable Demo Analytics'
                    : 'Printing available on Web',
              ),
            ),
            const Text(
              'CSV/PDF file generation is not connected. The Web print dialog can save the local report as PDF.',
            ),
          ] else ...[
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: section == 'Accounts'
                    ? 'Search sample account name/ID'
                    : section == 'Jobs'
                    ? 'Search sample job/company'
                    : 'Search case, category or reason',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                ModuleSelect(
                  label: 'Status',
                  value: filter,
                  options: {
                    '': 'All statuses',
                    for (final s
                        in section == 'Accounts'
                            ? ['Active', 'Restricted', 'Suspended']
                            : section == 'Jobs'
                            ? ['Published', 'Pending Review', 'Removed']
                            : DisputeState.values.map((s) => s.label).toList())
                      s: s,
                  },
                  onChanged: (v) => setState(() => filter = v),
                ),
                if (section == 'Accounts')
                  ModuleSelect(
                    label: 'Role',
                    value: roleFilter,
                    options: const {
                      '': 'All roles',
                      'Job Seeker': 'Job Seeker',
                      'Employer': 'Employer',
                    },
                    onChanged: (v) => setState(() => roleFilter = v),
                  ),
                TextButton(
                  onPressed: () => setState(() {
                    search.clear();
                    filter = '';
                    roleFilter = '';
                  }),
                  child: const Text('Clear filters'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (section == 'Accounts') ...[
              if (accounts.isEmpty)
                const ModuleState(
                  title: 'No sample accounts found',
                  message: 'Try another search or status.',
                ),
              for (final a in accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: WorkspaceCard(
                    title: a.name,
                    subtitle: '${a.role} • ${a.state} • ${a.id}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton(
                          onPressed: () => moduleModal<void>(
                            context,
                            ModalBody(
                              title: a.name,
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                              children: [
                                Text(
                                  'Fictional account ${a.id}\nRole: ${a.role}\nStanding: ${a.state}\nNo real identity, verification or trust score is asserted.',
                                ),
                              ],
                            ),
                          ),
                          child: const Text('View Sample Account Details'),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in <(String, String)>[
                              ('Restrict', 'Restricted'),
                              ('Suspend', 'Suspended'),
                              ('Reactivate', 'Active'),
                            ])
                              OutlinedButton(
                                onPressed: a.state == item.$2
                                    ? null
                                    : () => moduleModal<void>(
                                        context,
                                        AdminActionForm(
                                          store: store,
                                          target: a.id,
                                          kind: 'Account',
                                          action: item.$2,
                                          title: '${item.$1} sample account',
                                        ),
                                      ),
                                child: Text('${item.$1} (demo)'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (section == 'Jobs') ...[
              if (jobs.isEmpty)
                const ModuleState(
                  title: 'No sample job posts found',
                  message: 'Change your filters.',
                ),
              for (final j in jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: WorkspaceCard(
                    title: j.title,
                    subtitle: '${j.company} • ${j.state}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          j.reason.isEmpty
                              ? 'Sample moderation context. This is not a real employer posting.'
                              : 'Demo removal reason: ${j.reason}',
                        ),
                        OutlinedButton(
                          onPressed: () => moduleModal<void>(
                            context,
                            ModalBody(
                              title: 'Sample moderation detail',
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                              children: [
                                Text(
                                  '${j.id}\n${j.title}\n${j.company}\nStatus: ${j.state}\nNo live posting or employer permissions are modified.',
                                ),
                              ],
                            ),
                          ),
                          child: const Text('View Moderation Detail'),
                        ),
                        OutlinedButton(
                          onPressed: j.state == 'Removed'
                              ? null
                              : () => moduleModal<void>(
                                  context,
                                  AdminActionForm(
                                    store: store,
                                    target: j.id,
                                    kind: 'Job',
                                    action: 'Removed',
                                    title: 'Remove sample posting',
                                  ),
                                ),
                          child: const Text('Remove Job (demo)'),
                        ),
                        const Text(
                          'Job approval backend is not connected; no actual publication is performed.',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (section == 'Disputes') ...[
              DemoStats({
                'Matching cases': cases.length,
                'Unresolved': cases.where((d) => !d.state.terminal).length,
                'Terminal': cases.where((d) => d.state.terminal).length,
              }),
              if (cases.isEmpty)
                const ModuleState(
                  title: 'No demo disputes found',
                  message: 'Payment issues and received-evaluation reports create linked local cases here.',
                ),
              for (final d in cases.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: WorkspaceCard(
                    title: '${d.id} • ${d.subject}',
                    subtitle: '${d.category} • ${d.state.label}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          d.reason,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Opened ${jobDate(d.timeline.first.$2)} • sample parties only',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => context.push(
                            '${AppRoutes.adminDemoDisputes}/${d.id}',
                          ),
                          child: const Text('Review Demo Case'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      );
    },
  );
}

class AdminActionForm extends StatefulWidget {
  const AdminActionForm({
    super.key,
    required this.store,
    required this.target,
    required this.kind,
    required this.action,
    required this.title,
  });
  final Phase4Store store;
  final String target, kind, action, title;
  @override
  State<AdminActionForm> createState() => _AdminActionFormState();
}

class _AdminActionFormState extends State<AdminActionForm> {
  late final keyName = 'admin-action:${widget.target}:${widget.action}';
  late final reason = TextEditingController(
    text: widget.store.formDrafts[keyName] ?? '',
  );
  String? error;
  bool done = false;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalBody(
    title: done ? 'Demo action recorded' : widget.title,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(done ? 'Done' : 'Cancel (keep draft)'),
      ),
      if (!done)
        FilledButton(
          onPressed: () async {
            if (reason.text.trim().isEmpty) {
              setState(() => error = 'Enter a reason.');
              return;
            }
            if (!await demoConfirm(
              context,
              widget.title,
              'This changes fictional session data only. No real account/job will change.',
            )) {
              return;
            }
            if (!mounted || !context.mounted) return;
            try {
              if (widget.kind == 'Account') {
                widget.store.accountAction(
                  widget.target,
                  widget.action,
                  reason.text,
                );
              } else {
                widget.store.removeJob(widget.target, reason.text);
              }
              widget.store.formDrafts.remove(keyName);
              setState(() => done = true);
            } on StateError catch (e) {
              setState(() => error = e.message.toString());
            }
          },
          child: const Text('Confirm Demo Action'),
        ),
    ],
    children: [
      const Text(
        'DEMO ONLY • No Supabase mutation or notification. The sample audit entry is local and not tamper-proof.',
      ),
      if (done)
        const Text(
          'The local sample state and demo audit history have been updated.',
        )
      else ...[
        TextField(
          controller: reason,
          maxLength: 1000,
          minLines: 3,
          maxLines: 6,
          onChanged: (v) => widget.store.formDrafts[keyName] = v,
          decoration: const InputDecoration(labelText: 'Reason (required)'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ],
  );
}

class DisputeDetailPage extends StatefulWidget {
  const DisputeDetailPage({super.key, required this.disputeId, this.store});
  final String disputeId;
  final Phase4Store? store;
  @override
  State<DisputeDetailPage> createState() => _DisputeDetailPageState();
}

class _DisputeDetailPageState extends State<DisputeDetailPage> {
  late final store = widget.store ?? Phase4Store.session;
  late final keyName = 'remarks:${widget.disputeId}';
  late final remarks = TextEditingController(
    text:
        store.formDrafts[keyName] ??
        store.dispute(widget.disputeId)?.remarks ??
        '',
  );
  @override
  void dispose() {
    remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final d = store.dispute(widget.disputeId),
          p = d?.linkId == null ? null : store.payment(d!.linkId!);
      return DemoPage(
        title: 'Demo Dispute Details',
        sidebar: d == null
            ? const []
            : [
                WorkspaceCard(
                  title: 'Case actions',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed:
                            d.state.terminal ||
                                d.state == DisputeState.investigating
                            ? null
                            : () => moduleModal<void>(
                                context,
                                DisputeActionForm(
                                  store: store,
                                  disputeId: d.id,
                                  next: DisputeState.investigating,
                                ),
                              ),
                        child: const Text('Investigate (demo)'),
                      ),
                      OutlinedButton(
                        onPressed:
                            d.state.terminal ||
                                d.state == DisputeState.pendingInfo
                            ? null
                            : () => moduleModal<void>(
                                context,
                                DisputeActionForm(
                                  store: store,
                                  disputeId: d.id,
                                  next: DisputeState.pendingInfo,
                                ),
                              ),
                        child: const Text('Request More Information'),
                      ),
                      FilledButton(
                        onPressed: d.state.terminal
                            ? null
                            : () => moduleModal<void>(
                                context,
                                DisputeActionForm(
                                  store: store,
                                  disputeId: d.id,
                                  next: DisputeState.resolved,
                                ),
                              ),
                        child: const Text('Resolve (demo)'),
                      ),
                      OutlinedButton(
                        onPressed: d.state.terminal
                            ? null
                            : () => moduleModal<void>(
                                context,
                                DisputeActionForm(
                                  store: store,
                                  disputeId: d.id,
                                  next: DisputeState.rejected,
                                ),
                              ),
                        child: const Text('Reject (demo)'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                WorkspaceCard(
                  title: 'Internal demo remarks',
                  subtitle: 'Visible in this admin preview only; no server privacy guarantee is claimed.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: remarks,
                        maxLength: 2000,
                        minLines: 3,
                        maxLines: 6,
                        onChanged: (v) => store.formDrafts[keyName] = v,
                        decoration: const InputDecoration(
                          labelText: 'Internal remarks',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          try {
                            store.saveRemarks(d.id, remarks.text);
                            store.formDrafts.remove(keyName);
                            demoMessage(context, 'Demo remarks saved locally');
                          } on StateError catch (e) {
                            demoMessage(context, e.message.toString());
                          }
                        },
                        child: const Text('Save Remarks (demo)'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                WorkspaceCard(
                  title: 'Local action history',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in store.audit.where(
                        (line) => line.contains(d.id),
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(line),
                        ),
                      const Text(
                        'Not a secure audit trail; production logging is not implemented.',
                      ),
                    ],
                  ),
                ),
              ],
        maxWidth: 1024,
        path: AppRoutes.adminDemoDisputes,
        role: 'administrator',
        back: AppRoutes.adminDemoDisputes,
        children: [
          const Phase3Notice(adminPreviewDisclaimer),
          if (d == null)
            const ModuleState(
              title: 'Case unavailable',
              message:
                  'No case exists with this ID in the current demo session.',
            )
          else ...[
            WorkspaceCard(
              title: d.id,
              subtitle: '${d.category} • ${d.state.label}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WorkspaceInfo('Subject', d.subject),
                  WorkspaceInfo('Parties', 'Demo candidate / demo employer'),
                  WorkspaceInfo('Initial report', d.reason),
                  if (d.linkId != null)
                    WorkspaceInfo('Linked sample record', d.linkId!),
                  if (d.outcome.isNotEmpty) WorkspaceInfo('Outcome', d.outcome),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const SizedBox(height: 20),
            WorkspaceCard(
              title: 'Case timeline',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in d.timeline)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(entry.$1.label),
                      subtitle: Text(
                        '${jobDate(entry.$2)} • ${demoTime(entry.$2)} • demo',
                      ),
                    ),
                ],
              ),
            ),
            if (d.requests.isNotEmpty) ...[
              const SizedBox(height: 20),
              WorkspaceCard(
                title: 'Information requests',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final request in d.requests) Text(request)],
                ),
              ),
            ],
            const SizedBox(height: 20),
            WorkspaceCard(
              title: 'Related sample evidence',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (p != null) ...[
                    Text(
                      'External payment record: ${sampleMoney(p.amount)} • ${p.state.label}',
                    ),
                    if (p.proof != null)
                      AttachmentTile(p.proof!)
                    else
                      const Text('No payment proof provided'),
                  ] else
                    const Text(
                      'No file evidence is attached. The report reason and linked sample record are available above.',
                    ),
                  const ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Protected conversation access'),
                    children: [
                      Text(
                        'Unavailable. Real private messages require server-authorized dispute scope and immutable access audit logging. This preview never queries protected conversations.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const SizedBox(height: 20),
          ],
        ],
      );
    },
  );
}

class DisputeActionForm extends StatefulWidget {
  const DisputeActionForm({
    super.key,
    required this.store,
    required this.disputeId,
    required this.next,
  });
  final Phase4Store store;
  final String disputeId;
  final DisputeState next;
  @override
  State<DisputeActionForm> createState() => _DisputeActionFormState();
}

class _DisputeActionFormState extends State<DisputeActionForm> {
  late final keyName = 'case-action:${widget.disputeId}:${widget.next.name}';
  late final text = TextEditingController(
    text: widget.store.formDrafts[keyName] ?? '',
  );
  late String party =
      widget.store.formDrafts['$keyName:party'] ?? 'Both parties';
  late String outcome = widget.store.formDrafts['$keyName:outcome'] ?? '';
  String error = '';
  bool done = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requesting = widget.next == DisputeState.pendingInfo,
        terminal = widget.next.terminal;
    return ModalBody(
      title: done
          ? 'Demo case updated'
          : requesting
          ? 'Request More Information'
          : '${widget.next.label} demo case',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(done ? 'Done' : 'Cancel (keep draft)'),
        ),
        if (!done)
          FilledButton(
            onPressed: () async {
              if (terminal && outcome.isEmpty) {
                setState(
                  () => error = 'Choose an outcome or rejection reason.',
                );
                return;
              }
              if (text.text.trim().isEmpty) {
                setState(
                  () => error = 'Enter the required explanation/details.',
                );
                return;
              }
              if (!await demoConfirm(
                context,
                'Update demo case?',
                'The sample timeline/status will change. No user is contacted and no financial correction occurs.',
              )) {
                return;
              }
              if (!mounted || !context.mounted) return;
              try {
                widget.store.updateDispute(
                  widget.disputeId,
                  widget.next,
                  '${outcome.isEmpty ? '' : '$outcome: '}${text.text}',
                  party: party,
                );
                widget.store.formDrafts.remove(keyName);
                widget.store.formDrafts.remove('$keyName:party');
                widget.store.formDrafts.remove('$keyName:outcome');
                setState(() => done = true);
              } on StateError catch (e) {
                setState(() => error = e.message.toString());
              }
            },
            child: const Text('Confirm Demo Case Action'),
          ),
      ],
      children: [
        const Text(
          'DEMO ONLY • No server resolution, private message access, notification or payment reversal.',
        ),
        if (done)
          Text('Sample status: ${widget.next.label}')
        else ...[
          const SizedBox(height: 16),
          if (requesting)
            ModuleSelect(
              label: 'Request from',
              value: party,
              options: const {
                'Both parties': 'Both parties',
                'Worker': 'Worker',
                'Employer': 'Employer',
              },
              onChanged: (v) => setState(() {
                party = v;
                widget.store.formDrafts['$keyName:party'] = v;
              }),
            ),
          if (terminal)
            ModuleSelect(
              label: widget.next == DisputeState.resolved
                  ? 'Resolution outcome'
                  : 'Rejection reason',
              value: outcome,
              options: {
                '': 'Select one',
                for (final option
                    in widget.next == DisputeState.resolved
                        ? [
                            'Worker concern upheld',
                            'Employer concern upheld',
                            'Mutual agreement',
                            'No correction needed',
                          ]
                        : [
                            'Insufficient evidence',
                            'Duplicate case',
                            'Outside scope',
                            'Other',
                          ])
                  option: option,
              },
              onChanged: (v) => setState(() {
                outcome = v;
                widget.store.formDrafts['$keyName:outcome'] = v;
              }),
            ),
          TextField(
            controller: text,
            maxLength: 900,
            minLines: 4,
            maxLines: 7,
            onChanged: (v) => widget.store.formDrafts[keyName] = v,
            decoration: const InputDecoration(
              labelText: 'Explanation / details (required)',
            ),
          ),
          if (error.isNotEmpty)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ],
    );
  }
}

String adminReportHtml(Map<String, int> metrics) {
  const escape = HtmlEscape();
  return '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>JobMate Demo Analytics</title><style>body{font:16px system-ui;max-width:800px;margin:32px auto;padding:24px;color:#0f172a}td,th{padding:12px;text-align:left;border-bottom:1px solid #cbd5e1}table{width:100%}@media print{button{display:none}}@page{size:A4;margin:18mm}</style><button onclick="window.print()">Print / Save as PDF</button><h1>JobMate • DEMO Analytics</h1><p>Fictional session data only; not actual platform statistics.</p><table>${metrics.entries.map((e) => '<tr><th>${escape.convert(e.key)}</th><td>${e.value}</td></tr>').join()}</table></html>';
}
