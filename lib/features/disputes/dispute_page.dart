import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'dispute_gateway.dart';
import 'dispute_presentation.dart';
import 'dispute_submit_dialog.dart';

Future<void> showDisputeDetailsModal(
  BuildContext context, {
  required String disputeId,
  required DisputeGateway gateway,
  required String role,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) {
    final compact = MediaQuery.sizeOf(dialogContext).width < 600;
    final page = DisputePage(
      admin: false,
      disputeId: disputeId,
      gateway: gateway,
      role: role,
      embedded: true,
    );
    if (compact) return Dialog.fullscreen(child: page);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 920,
        height: MediaQuery.sizeOf(dialogContext).height * .9,
        child: page,
      ),
    );
  },
);

class DisputePage extends StatefulWidget {
  const DisputePage({
    super.key,
    required this.admin,
    this.disputeId,
    this.gateway,
    this.role,
    this.structuredFinalization = structuredDisputeFinalizationEnabled,
    this.relatedCases = relatedCasesEnabled,
    this.historicalClassification = historicalClassificationEnabled,
    this.groupedList = groupedDisputeListEnabled,
    this.embedded = false,
  });
  final bool admin;
  final String? disputeId;
  final DisputeGateway? gateway;
  final String? role;
  final bool structuredFinalization;
  final bool relatedCases;
  final bool historicalClassification;
  final bool groupedList;
  final bool embedded;
  @override
  State<DisputePage> createState() => _DisputePageState();
}

class _DisputePageState extends State<DisputePage> with WidgetsBindingObserver {
  static const pageSize = 20;
  final TextEditingController _searchController = TextEditingController();
  late DisputeGateway gateway;
  String role = 'job_seeker';
  String accountStatus = 'active';
  bool loading = true,
      evidenceBusy = false,
      incidentBusy = false,
      relatedCasesBusy = false,
      historicalClassificationBusy = false,
      terminalBusy = false,
      hasMore = false;
  int offset = 0;
  int totalCount = 0;
  int totalDisputeCount = 0;
  String? categoryFilter;
  String? statusFilter;
  String? error;
  List<Map<String, dynamic>> rows = [],
      history = [],
      evidence = [],
      evidenceEvents = [];
  List<Map<String, dynamic>> relatedCaseRows = [];
  Map<String, dynamic>? detail;
  Map<String, dynamic>? incidentCase;
  Map<String, dynamic>? historicalClassificationResult;
  String? incidentCaseError;
  String? relatedCasesError;
  Timer? _refreshTimer;
  StreamSubscription<AuthState>? _authSubscription;
  String? _actor;
  bool _loadInFlight = false;
  bool _reloadAfterLoad = false;
  bool _modalSessionEnded = false;
  String get root =>
      widget.admin ? AppRoutes.adminDisputes : AppRoutes.disputes;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    gateway =
        widget.gateway ?? SupabaseDisputeGateway(Supabase.instance.client);
    if (gateway case final SupabaseDisputeGateway source) {
      final client = source.client;
      _actor = client.auth.currentUser?.id;
      _authSubscription = client.auth.onAuthStateChange.listen((event) {
        final nextActor = event.session?.user.id;
        if (nextActor == _actor) return;
        _actor = nextActor;
        _modalSessionEnded = widget.embedded;
        gateway = SupabaseDisputeGateway(client);
        if (!mounted) return;
        setState(() {
          rows = [];
          detail = null;
          history = [];
          evidence = [];
          evidenceEvents = [];
          relatedCaseRows = [];
          incidentCase = null;
          historicalClassificationResult = null;
          offset = 0;
          loading = nextActor != null && !_modalSessionEnded;
          error = _modalSessionEnded
              ? 'Your account changed. Close and reopen Dispute Details.'
              : nextActor == null
              ? 'Sign in to view disputes.'
              : null;
        });
        if (nextActor != null && !_modalSessionEnded) {
          if (_loadInFlight) {
            _reloadAfterLoad = true;
          } else {
            unawaited(_load());
          }
        }
      });
    }
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted &&
          ModalRoute.isCurrentOf(context) != false &&
          !_loadInFlight &&
          !evidenceBusy &&
          !incidentBusy &&
          !relatedCasesBusy &&
          !historicalClassificationBusy &&
          !terminalBusy) {
        unawaited(_load(quietly: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.isCurrentOf(context) != false &&
        !_loadInFlight &&
        !evidenceBusy) {
      unawaited(_load(quietly: true));
    }
  }

  @override
  void didUpdateWidget(covariant DisputePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.disputeId != widget.disputeId ||
        oldWidget.admin != widget.admin ||
        oldWidget.structuredFinalization != widget.structuredFinalization ||
        oldWidget.relatedCases != widget.relatedCases ||
        oldWidget.historicalClassification != widget.historicalClassification ||
        oldWidget.groupedList != widget.groupedList ||
        oldWidget.embedded != widget.embedded) {
      if (oldWidget.disputeId != widget.disputeId) {
        historicalClassificationResult = null;
      }
      if (_loadInFlight) {
        _reloadAfterLoad = true;
      } else {
        _load();
      }
    }
  }

  Future<void> _load({bool quietly = false}) async {
    if (_loadInFlight || _modalSessionEnded) return;
    _loadInFlight = true;
    final gateway = this.gateway;
    final requestedId = widget.disputeId;
    final requestedAdmin = widget.admin;
    bool current() =>
        mounted &&
        identical(gateway, this.gateway) &&
        requestedId == widget.disputeId &&
        requestedAdmin == widget.admin;
    setState(() {
      if (!quietly) {
        loading = true;
        error = null;
      }
    });
    try {
      var nextRole = widget.role;
      var nextStatus = 'active';
      if (nextRole == null || gateway is SupabaseDisputeGateway) {
        final client = Supabase.instance.client;
        final id = client.auth.currentUser?.id;
        if (id == null) throw StateError('Sign in to view disputes.');
        final profile = await client
            .from('users')
            .select('role,status')
            .eq('user_id', id)
            .single();
        if (client.auth.currentUser?.id != id) {
          throw StateError('Your account changed.');
        }
        nextRole = profile['role'] as String;
        nextStatus = profile['status'] as String;
      }
      final id = requestedId;
      final useGroupedList = id == null && widget.admin && widget.groupedList;
      final search = _searchController.text.trim();
      Future<List<Map<String, dynamic>>> loadGroupedPage(int pageOffset) =>
          gateway.groupedAdminList(
            search: search.isEmpty ? null : search,
            category: categoryFilter,
            status: statusFilter,
            limit: pageSize,
            offset: pageOffset,
          );
      var resolvedOffset = offset;
      var nextRows = id == null
          ? useGroupedList
                ? await loadGroupedPage(resolvedOffset)
                : await gateway.list(
                    widget.admin,
                    limit: pageSize + 1,
                    offset: resolvedOffset,
                  )
          : <Map<String, dynamic>>[];
      if (useGroupedList && nextRows.isEmpty && resolvedOffset > 0) {
        final firstPage = await loadGroupedPage(0);
        if (firstPage.isEmpty) {
          resolvedOffset = 0;
          nextRows = firstPage;
        } else {
          final availableCount = firstPage.first['total_count'] as int;
          final lastPageOffset = ((availableCount - 1) ~/ pageSize) * pageSize;
          resolvedOffset = lastPageOffset;
          nextRows = lastPageOffset == 0
              ? firstPage
              : await loadGroupedPage(lastPageOffset);
          if (nextRows.isEmpty) {
            resolvedOffset = 0;
            nextRows = firstPage;
          }
        }
      }
      final nextDetail = id == null
          ? null
          : await gateway.details(id, widget.admin);
      final nextHistory = id == null
          ? <Map<String, dynamic>>[]
          : await gateway.history(id, widget.admin);
      final nextEvidence = id == null
          ? <Map<String, dynamic>>[]
          : await gateway.evidence(id, widget.admin);
      final nextEvidenceEvents = id == null
          ? <Map<String, dynamic>>[]
          : await gateway.evidenceHistory(id, widget.admin);
      Map<String, dynamic>? nextIncidentCase;
      String? nextIncidentCaseError;
      if (id != null &&
          widget.admin &&
          (widget.groupedList ||
              widget.structuredFinalization ||
              widget.historicalClassification)) {
        try {
          nextIncidentCase = await gateway.incidentCase(id);
        } catch (_) {
          nextIncidentCaseError = 'Unable to load the Incident Case.';
        }
      }
      var nextRelatedCases = <Map<String, dynamic>>[];
      String? nextRelatedCasesError;
      if (id != null && widget.admin && widget.relatedCases) {
        try {
          nextRelatedCases = await gateway.relatedCases(id);
        } catch (error) {
          nextRelatedCasesError = _relatedCaseReadError(error);
        }
      }
      if (!current()) return;
      setState(() {
        error = null;
        role = nextRole!;
        accountStatus = nextStatus;
        offset = resolvedOffset;
        rows = useGroupedList ? nextRows : nextRows.take(pageSize).toList();
        totalCount = useGroupedList && nextRows.isNotEmpty
            ? nextRows.first['total_count'] as int
            : useGroupedList
            ? 0
            : resolvedOffset +
                  rows.length +
                  (nextRows.length > pageSize ? 1 : 0);
        totalDisputeCount = useGroupedList && nextRows.isNotEmpty
            ? nextRows.first['total_dispute_count'] as int
            : useGroupedList
            ? 0
            : totalCount;
        hasMore = useGroupedList
            ? resolvedOffset + nextRows.length < totalCount
            : nextRows.length > pageSize;
        detail = nextDetail;
        history = nextHistory;
        evidence = nextEvidence;
        evidenceEvents = nextEvidenceEvents;
        incidentCase = nextIncidentCase;
        incidentCaseError = nextIncidentCaseError;
        relatedCaseRows = nextRelatedCases;
        relatedCasesError = nextRelatedCasesError;
      });
    } catch (_) {
      if (current()) {
        setState(() {
          rows = [];
          detail = null;
          history = [];
          evidence = [];
          evidenceEvents = [];
          incidentCase = null;
          relatedCaseRows = [];
          historicalClassificationResult = null;
          error = 'Unable to load disputes. Check your access and try again.';
        });
      }
    } finally {
      _loadInFlight = false;
      if (current()) setState(() => loading = false);
      if (_reloadAfterLoad && mounted) {
        _reloadAfterLoad = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _edit({String? action}) async {
    if (action == null) {
      final disputeId = await showDisputeSubmitDialog(
        context,
        gateway: gateway,
      );
      if (disputeId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Dispute submitted successfully.'),
            action: widget.admin
                ? null
                : SnackBarAction(
                    label: 'View dispute',
                    onPressed: () => showDisputeDetailsModal(
                      context,
                      disputeId: disputeId,
                      gateway: gateway,
                      role: role,
                    ),
                  ),
          ),
        );
        offset = 0;
        await _load();
      }
      return;
    }
    if (const {'resolve', 'reject'}.contains(action)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resolve and Reject require Structured Finalization. No legacy terminal action was sent.',
            ),
          ),
        );
      }
      return;
    }
    var note = '';
    var busy = false;
    String? dialogError;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(action.replaceAll('_', ' ')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogTextField(
                  enabled: !busy,
                  maxLines: 4,
                  maxLength: 2000,
                  labelText: 'Reason or information',
                  onChanged: (value) => note = value,
                ),
                if (dialogError != null)
                  Text(
                    dialogError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (action != 'investigate' && note.trim().isEmpty) {
                        update(
                          () => dialogError = 'Complete the required fields.',
                        );
                        return;
                      }
                      update(() {
                        busy = true;
                        dialogError = null;
                      });
                      try {
                        await gateway.action(
                          widget.disputeId!,
                          action,
                          note.trim(),
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (_) {
                        update(() {
                          busy = false;
                          dialogError = 'Unable to save. Check the details and try again.';
                        });
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dispute saved.')));
      await _load();
    }
  }

  String _finalizationError(Object error) {
    if (error is PostgrestException &&
        const {'42501', '28000'}.contains(error.code)) {
      return 'You are not authorized to finalize this dispute. Refresh and try again.';
    }
    return 'Unable to finalize this dispute. Check the finding and try again.';
  }

  String _incidentLinkError(Object error) {
    if (error is PostgrestException &&
        const {'42501', '28000'}.contains(error.code)) {
      return 'You are not authorized to link this dispute to an incident.';
    }
    return 'Unable to link this dispute. Check the incident and try again.';
  }

  Future<void> _finalize(String terminalAction) async {
    var reason = '';
    DisputeFindingOutcome? outcome;
    var busy = false;
    String? dialogError;
    final allowedOutcomes = DisputeFindingOutcome.values
        .where((value) => terminalAction != 'reject' || value.allowedForReject)
        .toList(growable: false);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            terminalAction == 'reject'
                ? 'Reject dispute with finding'
                : 'Resolve dispute with finding',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<DisputeFindingOutcome>(
                  initialValue: outcome,
                  decoration: const InputDecoration(labelText: 'Final outcome'),
                  items: [
                    for (final value in allowedOutcomes)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => update(() {
                          outcome = value;
                          dialogError = null;
                        }),
                ),
                const SizedBox(height: 12),
                _DialogTextField(
                  enabled: !busy,
                  maxLines: 4,
                  maxLength: 2000,
                  labelText: 'Finding reason',
                  onChanged: (value) => reason = value,
                ),
                if (terminalAction == 'reject')
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Rejected cases may only be recorded as no violation or inconclusive.',
                    ),
                  ),
                if (dialogError != null)
                  Text(
                    dialogError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final selectedOutcome = outcome;
                      if (selectedOutcome == null || reason.trim().isEmpty) {
                        update(
                          () => dialogError =
                              'Select a final outcome and enter a reason.',
                        );
                        return;
                      }
                      update(() {
                        busy = true;
                        dialogError = null;
                      });
                      try {
                        await gateway.finalize(
                          widget.disputeId!,
                          selectedOutcome,
                          reason,
                          terminalAction,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        if (context.mounted) {
                          update(() {
                            busy = false;
                            dialogError = _finalizationError(error);
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Confirm finding'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            terminalAction == 'reject'
                ? 'Dispute rejected with a final finding.'
                : 'Dispute resolved with a final finding.',
          ),
        ),
      );
      await _load();
    }
  }

  bool _incidentManagementLocked(Map<String, dynamic>? currentCase) {
    final status = detail?['status'] as String?;
    final incidentId = currentCase?['incident_id'] as String?;
    final effectiveOutcome = currentCase?['effective_outcome'] as String?;
    return const {'resolved', 'rejected'}.contains(status) &&
        incidentId != null &&
        incidentId.isNotEmpty &&
        effectiveOutcome != null &&
        effectiveOutcome.isNotEmpty;
  }

  Future<void> _refreshIncidentCase() async {
    if (incidentBusy || widget.disputeId == null) return;
    setState(() {
      incidentBusy = true;
      incidentCaseError = null;
    });
    try {
      final currentCase = await gateway.incidentCase(widget.disputeId!);
      if (!mounted) return;
      setState(() => incidentCase = currentCase);
    } catch (_) {
      if (mounted) {
        setState(() => incidentCaseError = 'Unable to load the Incident Case.');
      }
    } finally {
      if (mounted) setState(() => incidentBusy = false);
    }
  }

  Future<void> _manageIncident() async {
    if (incidentBusy ||
        widget.disputeId == null ||
        _incidentManagementLocked(incidentCase)) {
      return;
    }
    setState(() => incidentBusy = true);
    try {
      final linkedIncidentId = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _IncidentLinkDialog(
          errorMessage: _incidentLinkError,
          onSave: (incidentId, reason) => gateway.linkIncident(
            widget.disputeId!,
            incidentId: incidentId,
            reason: reason,
          ),
        ),
      );
      if (linkedIncidentId == null || !mounted) return;

      final verifiedCase = await gateway.incidentCase(widget.disputeId!);
      if (!mounted) return;
      if (verifiedCase['incident_id'] != linkedIncidentId) {
        throw StateError('The incident link could not be verified.');
      }
      setState(() {
        incidentCase = verifiedCase;
        incidentCaseError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Incident Case updated.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_incidentLinkError(error))));
      }
    } finally {
      if (mounted) setState(() => incidentBusy = false);
    }
  }

  Future<void> _prepareStructuredFinalization(String action) async {
    if (terminalBusy || widget.disputeId == null) return;
    setState(() => terminalBusy = true);
    try {
      final currentCase = await gateway.incidentCase(widget.disputeId!);
      if (!mounted) return;
      final currentIncidentId = currentCase['incident_id'] as String?;
      setState(() {
        incidentCase = currentCase;
        incidentCaseError = null;
      });
      if (currentIncidentId == null || currentIncidentId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Link this Dispute from Incident Case before finalizing.',
            ),
          ),
        );
        return;
      }
      await _finalize(action);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_finalizationError(error))));
      }
    } finally {
      if (mounted) setState(() => terminalBusy = false);
    }
  }

  void _terminalAction(String action) {
    if (!widget.structuredFinalization) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Structured Finalization is disabled for this build. Resolve and Reject are unavailable.',
          ),
        ),
      );
      return;
    }
    _prepareStructuredFinalization(action);
  }

  Widget _incidentCaseSection() {
    final currentCase = incidentCase;
    final incidentId = currentCase?['incident_id'] as String?;
    final linked = incidentId != null && incidentId.isNotEmpty;
    final locked = _incidentManagementLocked(currentCase);

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Incident Case',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SelectableText(linked ? 'Incident ID: $incidentId' : 'Not linked'),
            if (incidentCaseError != null) ...[
              const SizedBox(height: 8),
              Text(
                incidentCaseError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: incidentBusy ? null : _refreshIncidentCase,
                child: const Text('Retry Incident Case'),
              ),
            ],
            if (locked) ...[
              const SizedBox(height: 8),
              const Text(
                'This finalized case is read-only. Incident corrections require the separately reviewed Correction workflow.',
              ),
            ] else if (widget.admin) ...[
              if (detail?['status'] == 'investigating' && !linked) ...[
                const SizedBox(height: 8),
                const Text(
                  'Resolve and Reject are disabled until Incident Case linking is completed.',
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: incidentBusy ? null : _manageIncident,
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(
                  incidentBusy ? 'Updating Incident…' : 'Manage Incident',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create a distinct Incident or enter an existing Incident UUID. Never group reports only because they share an Assignment.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _historicalClassificationError(Object error) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (error.code == '23505' || message.contains('already classified')) {
        return 'This historical report is already classified.';
      }
      if (message.contains('pending incident appeal')) {
        return 'A pending Appeal must be reviewed before classification.';
      }
      if (message.contains('link the historical report')) {
        return 'Link this historical report to an Incident before classification.';
      }
      if (message.contains('outcome differs from this incident')) {
        return 'The selected outcome conflicts with the Incident finding. Review the Incident identity and outcome.';
      }
      if (const {'42501', '28000'}.contains(error.code)) {
        return 'You are not authorized to classify this historical report.';
      }
      if (error.code == '23514') {
        return 'This report is not currently eligible for historical classification.';
      }
    }
    return 'Unable to classify this historical report. Check the connection and try again.';
  }

  Future<void> _classifyHistoricalFinding() async {
    if (historicalClassificationBusy || widget.disputeId == null) return;
    final originalStatus = detail?['status'] as String?;
    if (!const {'resolved', 'rejected'}.contains(originalStatus)) return;
    setState(() => historicalClassificationBusy = true);
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HistoricalFindingDialog(
          terminalStatus: originalStatus!,
          errorMessage: _historicalClassificationError,
          onSave: (outcome, reason) => gateway.classifyHistoricalFinding(
            widget.disputeId!,
            outcome,
            reason,
          ),
        ),
      );
      if (result == null || !mounted) return;
      if (result['preserved_status'] != originalStatus) {
        throw StateError('Historical classification changed terminal status.');
      }
      historicalClassificationResult = result;
      await _load();
      if (!mounted) return;
      if (detail?['status'] != originalStatus) {
        throw StateError('Historical classification changed terminal status.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Historical finding recorded.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_historicalClassificationError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => historicalClassificationBusy = false);
    }
  }

  Widget _historicalFindingSection() {
    final status = detail?['status'] as String?;
    final incidentId = incidentCase?['incident_id'] as String?;
    final linked = incidentId != null && incidentId.isNotEmpty;
    final appealPending = incidentCase?['appeal_pending'] == true;
    final result = historicalClassificationResult;
    final disabled =
        historicalClassificationBusy ||
        !linked ||
        appealPending ||
        result != null;

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historical Finding Review',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Record an evidence-based structured decision for this historical report. This does not change its resolved or rejected status and does not attest Trust Score coverage.',
            ),
            const SizedBox(height: 8),
            if (!linked)
              const Text(
                'No Incident is linked. Complete Incident Case linking first.',
              )
            else if (appealPending)
              const Text(
                'A pending Appeal must be reviewed before historical classification.',
              )
            else if (result != null)
              Text(
                'Recorded outcome: ${result['outcome']}. Preserved status: ${result['preserved_status']}.',
              )
            else
              Text(
                'Incident linked: $incidentId. Report-level eligibility will be validated by the server.',
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: disabled ? null : _classifyHistoricalFinding,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                historicalClassificationBusy
                    ? 'Reviewing…'
                    : 'Review Historical Finding',
              ),
            ),
            if (result == null && linked && !appealPending)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'An existing report decision or conflicting Incident finding will be rejected by the backend.',
                ),
              ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Current terminal status: $status'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshRelatedCases() async {
    if (relatedCasesBusy || widget.disputeId == null) return;
    setState(() {
      relatedCasesBusy = true;
      relatedCasesError = null;
    });
    try {
      final rows = await gateway.relatedCases(widget.disputeId!);
      if (!mounted) return;
      setState(() => relatedCaseRows = rows);
    } catch (error) {
      if (mounted) {
        setState(() => relatedCasesError = _relatedCaseReadError(error));
      }
    } finally {
      if (mounted) setState(() => relatedCasesBusy = false);
    }
  }

  String _relatedCaseError(Object error) {
    if (error is PostgrestException) {
      if (error.code == '23505') return 'These Incidents are already related.';
      if (error.code == '23514') {
        return 'The selected Incident is incompatible or belongs to another Related Case group.';
      }
      if (error.code == '42501') {
        return 'You are not authorized to manage every affected case.';
      }
    }
    return 'Unable to update Related Cases. Refresh and try again.';
  }

  String _relatedCaseReadError(Object error) {
    if (error is PostgrestException) {
      if (const {'42501', '28000'}.contains(error.code)) {
        return 'You are not authorized to view every case in this Related Group.';
      }
      if (error.code == 'PGRST202') {
        return 'The Related Cases read RPC is unavailable. Verify the deployed backend contract.';
      }
    }
    if (error is FormatException) {
      return 'Related Cases returned an incompatible response. Retry after verifying the backend version.';
    }
    return 'Unable to reach Related Cases. Check the connection and retry.';
  }

  Future<void> _addRelatedCase() async {
    if (relatedCasesBusy || widget.disputeId == null) return;
    setState(() => relatedCasesBusy = true);
    List<Map<String, dynamic>> candidates;
    try {
      candidates = await gateway.relatedCaseCandidates(widget.disputeId!);
    } catch (error) {
      if (mounted) {
        setState(() => relatedCasesError = _relatedCaseReadError(error));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_relatedCaseReadError(error))));
      }
      if (mounted) setState(() => relatedCasesBusy = false);
      return;
    }
    if (!mounted) return;
    setState(() => relatedCasesBusy = false);
    final linked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddRelatedCaseDialog(
        candidates: candidates,
        errorMessage: _relatedCaseError,
        onSave: (incidentId, reason) => gateway.linkRelatedCase(
          widget.disputeId!,
          targetIncidentId: incidentId,
          reason: reason,
        ),
      ),
    );
    if (linked == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Related Case added.')));
      await _refreshRelatedCases();
    }
  }

  Future<void> _removeRelatedCase(Map<String, dynamic> related) async {
    if (relatedCasesBusy || widget.disputeId == null) return;
    final incidentId = related['incident_id'] as String?;
    if (incidentId == null || incidentId.isEmpty) return;
    final removed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RemoveRelatedCaseDialog(
        incidentId: incidentId,
        errorMessage: _relatedCaseError,
        onSave: (reason) => gateway.removeRelatedCase(
          widget.disputeId!,
          targetIncidentId: incidentId,
          reason: reason,
        ),
      ),
    );
    if (removed == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Related Case removed.')));
      await _refreshRelatedCases();
    }
  }

  Widget _relatedCasesSection() => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Related Cases', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Cross-category references only. Incident identity, findings and Trust Score evidence remain separate.',
          ),
          if (relatedCasesError != null) ...[
            const SizedBox(height: 8),
            Text(
              relatedCasesError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: relatedCasesBusy ? null : _refreshRelatedCases,
              child: const Text('Retry Related Cases'),
            ),
          ] else if (relatedCasesBusy) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          ] else if (relatedCaseRows.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No related cases.'),
            ),
          ] else
            for (final related in relatedCaseRows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${related['category']} Incident'),
                subtitle: Text(
                  '${related['incident_id']}\nStatuses: ${_relatedStatuses(related['statuses'])}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Remove Related Case',
                  onPressed: relatedCasesBusy || relatedCasesError != null
                      ? null
                      : () => _removeRelatedCase(related),
                  icon: const Icon(Icons.link_off_outlined),
                ),
              ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: relatedCasesBusy || relatedCasesError != null
                ? null
                : _addRelatedCase,
            icon: const Icon(Icons.add_link_outlined),
            label: const Text('Add Related Case'),
          ),
        ],
      ),
    ),
  );

  String _relatedStatuses(Object? value) {
    if (value is List) {
      if (value.isEmpty) return 'None reported';
      return value.map((item) => '$item').join(', ');
    }
    return 'Unknown';
  }

  Future<void> _uploadEvidence() async {
    if (evidenceBusy || widget.disputeId == null) return;
    const types = XTypeGroup(
      label: 'Dispute evidence',
      extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: [types]);
    if (file == null) return;
    setState(() => evidenceBusy = true);
    try {
      final bytes = await file.readAsBytes();
      await gateway.uploadEvidence(
        widget.disputeId!,
        const Uuid().v4(),
        file.name,
        bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Evidence submitted.')));
      await _load();
    } on FormatException catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to submit evidence.')),
        );
      }
    } finally {
      if (mounted) setState(() => evidenceBusy = false);
    }
  }

  Future<void> _openEvidence(String path) async {
    try {
      final url = await gateway.evidenceUrl(path);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to open evidence.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open this evidence.')),
        );
      }
    }
  }

  void _applyGroupedFilters() {
    offset = 0;
    _load();
  }

  void _clearGroupedFilters() {
    _searchController.clear();
    setState(() {
      categoryFilter = null;
      statusFilter = null;
      offset = 0;
    });
    _load();
  }

  Widget _groupedListControls() => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ExpandableFilterBar(
            search: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Search Dispute, Incident or Related Group ID',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _applyGroupedFilters(),
            ),
            activeCount: [
              categoryFilter,
              statusFilter,
            ].where((value) => value != null).length,
            onClear: _clearGroupedFilters,
            filters: [
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  key: ValueKey(categoryFilter),
                  initialValue: categoryFilter,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('All categories'),
                    ),
                    DropdownMenuItem(
                      value: 'recruitment',
                      child: Text('Recruitment'),
                    ),
                    DropdownMenuItem(value: 'work', child: Text('Work')),
                    DropdownMenuItem(value: 'payment', child: Text('Payment')),
                  ],
                  onChanged: (value) => setState(() {
                    categoryFilter = value;
                    offset = 0;
                  }),
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  key: ValueKey(('status', statusFilter)),
                  initialValue: statusFilter,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All statuses')),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(
                      value: 'investigating',
                      child: Text('Investigating'),
                    ),
                    DropdownMenuItem(
                      value: 'pending_information',
                      child: Text('Pending information'),
                    ),
                    DropdownMenuItem(
                      value: 'resolved',
                      child: Text('Resolved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    statusFilter = value;
                    offset = 0;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _applyGroupedFilters,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _groupedListRow(Map<String, dynamic> row) {
    final groupId = row['related_group_id'] as String?;
    final children = (row['children'] as List).cast<Map<String, dynamic>>();
    final categories = (row['categories'] as List).join(', ');
    final summary = row['status_summary'] as String;
    final count = row['dispute_count'] as int;

    Widget childTile(Map<String, dynamic> child) => ListTile(
      title: Text('${child['category']} dispute · ${child['status']}'),
      subtitle: Text(
        'Dispute ID: ${child['dispute_id']}\n'
        'Incident ID: ${child['incident_id'] ?? 'Not linked'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go('$root/${child['dispute_id']}'),
    );

    if (groupId == null) {
      return Card(child: childTile(children.single));
    }
    return Card(
      child: ExpansionTile(
        key: ValueKey(row['entry_key']),
        leading: const Icon(Icons.account_tree_outlined),
        title: Text('Related Group $groupId'),
        subtitle: Text('$categories · $count disputes · $summary'),
        children: [for (final child in children) childTile(child)],
      ),
    );
  }

  Future<void> _openDispute(Map<String, dynamic> row) async {
    final id = row['dispute_id'] as String;
    if (widget.admin) {
      context.go('$root/$id');
      return;
    }
    await showDisputeDetailsModal(
      context,
      disputeId: id,
      gateway: gateway,
      role: role,
    );
    if (mounted) await _load(quietly: true);
  }

  Widget _disputeCard(Map<String, dynamic> row) => Card.outlined(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openDispute(row),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final identity = Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.gavel_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        disputeCategoryLabel(row['category']),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                );
                final badge = DisputeStatusBadge(row['status'] as String?);
                if (constraints.maxWidth < 430) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [identity, const SizedBox(height: 8), badge],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 12),
                    badge,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.schedule_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Submitted ${disputeDateTime(row['created_at'])}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => _openDispute(row),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('View dispute'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final status = detail?['status'] as String?;
    final terminal = status == 'resolved' || status == 'rejected';
    final decision = terminal
        ? history
              .where(
                (event) =>
                    event['new_status'] == status &&
                    const {'resolve', 'reject'}.contains(event['action']),
              )
              .firstOrNull
        : null;
    final currentIncidentId = incidentCase?['incident_id'] as String?;
    final incidentLinked =
        currentIncidentId != null && currentIncidentId.isNotEmpty;
    final structuredFinalizationReady =
        widget.structuredFinalization && incidentLinked;
    final canAddEvidence =
        !widget.admin &&
        const {
          'open',
          'investigating',
          'pending_information',
        }.contains(status) &&
        (accountStatus == 'active' || status == 'pending_information');
    final pageBody = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.disputeId == null ? 1360 : 1000,
        ),
        child: Padding(
          padding: ResponsiveLayout.pagePadding(context),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!),
                    if (!_modalSessionEnded)
                      TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                )
              : ListView(
                  children: [
                    if (widget.disputeId == null) ...[
                      if (!widget.admin)
                        PageHeading(
                          title: 'My Disputes',
                          description: 'Track submitted cases, review updates and provide requested information.',
                          actions: [
                            if (accountStatus == 'active')
                              FilledButton.icon(
                                onPressed: () => _edit(),
                                icon: const Icon(Icons.add),
                                label: const Text('Submit dispute'),
                              ),
                          ],
                        ),
                      if (widget.admin && widget.groupedList) ...[
                        _groupedListControls(),
                        const SizedBox(height: 12),
                      ],
                      if (rows.isEmpty)
                        const WorkspaceCard(
                          title: 'No disputes yet',
                          child: Text(
                            'Submitted disputes and their progress will appear here.',
                          ),
                        ),
                      if (widget.admin && widget.groupedList)
                        for (final row in rows) _groupedListRow(row)
                      else
                        ResponsiveGrid(
                          minItemWidth: 420,
                          maxColumns: 2,
                          equalRowHeight: true,
                          children: [for (final row in rows) _disputeCard(row)],
                        ),
                      if (widget.admin && widget.groupedList && rows.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Showing rows ${offset + 1}–${offset + rows.length} of $totalCount · $totalDisputeCount disputes',
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: offset == 0
                                ? null
                                : () {
                                    offset -= pageSize;
                                    _load();
                                  },
                            child: const Text('Previous'),
                          ),
                          TextButton(
                            onPressed: !hasMore
                                ? null
                                : () {
                                    offset += pageSize;
                                    _load();
                                  },
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  disputeCategoryLabel(detail?['category']),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Submitted ${disputeDateTime(detail?['created_at'])}',
                                ),
                              ],
                            ),
                          ),
                          DisputeStatusBadge(status),
                        ],
                      ),
                      if (!widget.embedded)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => context.go(root),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('All disputes'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _DisputeSection(
                        title: 'Case progress',
                        icon: Icons.route_outlined,
                        child: DisputeProgress(
                          status: status,
                          history: history,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DisputeSection(
                        title: 'Submitted description',
                        icon: Icons.description_outlined,
                        child: Text('${detail?['description'] ?? ''}'),
                      ),
                      if (widget.admin &&
                          (widget.groupedList ||
                              widget.structuredFinalization)) ...[
                        const SizedBox(height: 16),
                        _incidentCaseSection(),
                        const SizedBox(height: 12),
                      ],
                      if (widget.admin &&
                          widget.historicalClassification &&
                          const {'resolved', 'rejected'}.contains(status)) ...[
                        const SizedBox(height: 4),
                        _historicalFindingSection(),
                        const SizedBox(height: 12),
                      ],
                      if (widget.admin && widget.relatedCases) ...[
                        const SizedBox(height: 4),
                        _relatedCasesSection(),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        spacing: 8,
                        children: [
                          if (widget.admin && status == 'open')
                            FilledButton(
                              onPressed: () => _edit(action: 'investigate'),
                              child: const Text('Start investigation'),
                            ),
                          if (widget.admin && status == 'investigating') ...[
                            OutlinedButton(
                              onPressed: () =>
                                  _edit(action: 'request_information'),
                              child: const Text('Request information'),
                            ),
                            if (widget.structuredFinalization) ...[
                              FilledButton(
                                onPressed:
                                    terminalBusy || !structuredFinalizationReady
                                    ? null
                                    : () => _terminalAction('resolve'),
                                child: const Text('Resolve'),
                              ),
                              OutlinedButton(
                                onPressed:
                                    terminalBusy || !structuredFinalizationReady
                                    ? null
                                    : () => _terminalAction('reject'),
                                child: const Text('Reject'),
                              ),
                            ] else
                              const Text(
                                'Resolve and Reject require Structured Finalization to be enabled for this Debug build.',
                              ),
                            if (terminalBusy) const Text('Checking incident…'),
                          ],
                          if (!widget.admin && status == 'pending_information')
                            FilledButton(
                              onPressed: () =>
                                  _edit(action: 'respond_information'),
                              child: const Text('Submit information'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _DisputeSection(
                        title: 'Supporting evidence',
                        icon: Icons.attach_file,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (evidence.isEmpty)
                              const Text('No evidence submitted.'),
                            for (final item in evidence)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  item['mime_type'] == 'application/pdf'
                                      ? Icons.picture_as_pdf_outlined
                                      : Icons.image_outlined,
                                  size: 20,
                                ),
                                title: Text('${item['original_name']}'),
                                subtitle: Text(
                                  '${_evidenceType(item['mime_type'])} · ${item['size_bytes']} bytes · ${disputeDateTime(item['submitted_at'])}',
                                ),
                                trailing: const Icon(
                                  Icons.open_in_new,
                                  size: 20,
                                ),
                                onTap: () => _openEvidence(
                                  item['storage_path'] as String,
                                ),
                              ),
                            if (canAddEvidence)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                  onPressed: evidenceBusy
                                      ? null
                                      : _uploadEvidence,
                                  icon: const Icon(Icons.attach_file, size: 20),
                                  label: Text(
                                    evidenceBusy
                                        ? 'Uploading…'
                                        : 'Add evidence',
                                  ),
                                ),
                              ),
                            if (evidenceEvents.isNotEmpty) ...[
                              const Divider(),
                              Text(
                                'Evidence submission history',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              DisputeActivityTimeline(
                                events: evidenceEvents,
                                evidence: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DisputeSection(
                        title: 'Dispute history',
                        icon: Icons.history,
                        child: DisputeActivityTimeline(events: history),
                      ),
                      if (terminal) ...[
                        const SizedBox(height: 16),
                        _DisputeSection(
                          title: 'Resolution details',
                          icon: Icons.gavel_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(disputeStatusLabel(status)),
                              if (decision?['created_at'] != null)
                                Text(disputeDateTime(decision!['created_at'])),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
        ),
      ),
    );
    if (widget.embedded) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: 'Close dispute details',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(child: pageBody),
            ],
          ),
        ),
      );
    }
    return AppWorkspace(
      title: widget.admin ? 'Dispute management' : 'My disputes',
      path: root,
      role: widget.admin ? 'administrator' : role,
      child: pageBody,
    );
  }
}

String _evidenceType(Object? mimeType) => switch (mimeType) {
  'application/pdf' => 'PDF',
  'image/jpeg' => 'JPEG',
  'image/png' => 'PNG',
  'image/webp' => 'WebP',
  _ => 'Attachment',
};

class _DisputeSection extends StatelessWidget {
  const _DisputeSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _IncidentLinkDialog extends StatefulWidget {
  const _IncidentLinkDialog({required this.onSave, required this.errorMessage});

  final Future<String> Function(String? incidentId, String reason) onSave;
  final String Function(Object error) errorMessage;

  @override
  State<_IncidentLinkDialog> createState() => _IncidentLinkDialogState();
}

class _IncidentLinkDialogState extends State<_IncidentLinkDialog> {
  String? _mode;
  String _incidentId = '';
  String _reason = '';
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final existingIncident = _mode == 'existing';
    if (_mode == null ||
        _reason.trim().isEmpty ||
        (existingIncident && _incidentId.trim().isEmpty)) {
      setState(() {
        _error = 'Choose an incident option and complete the required fields.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final linkedIncidentId = await widget.onSave(
        existingIncident ? _incidentId.trim() : null,
        _reason.trim(),
      );
      if (mounted) Navigator.pop(context, linkedIncidentId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Manage Incident Case'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose explicitly. Disputes must not be grouped only because they share an Assignment.',
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              selected: _mode == 'new',
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create New Incident'),
              subtitle: const Text(
                'Use for a distinct real-world event after reviewing the case.',
              ),
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _mode = 'new';
                      _error = null;
                    }),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              selected: _mode == 'existing',
              leading: const Icon(Icons.link_outlined),
              title: const Text('Select Existing Incident'),
              subtitle: const Text(
                'Manual UUID entry is required; no authorized Incident directory is available.',
              ),
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _mode = 'existing';
                      _error = null;
                    }),
            ),
          ),
          if (_mode == 'existing') ...[
            const SizedBox(height: 12),
            _DialogTextField(
              enabled: !_busy,
              maxLines: 1,
              maxLength: 36,
              labelText: 'Existing Incident UUID',
              onChanged: (value) => _incidentId = value,
            ),
          ],
          const SizedBox(height: 12),
          _DialogTextField(
            enabled: !_busy,
            maxLines: 4,
            maxLength: 2000,
            labelText: 'Link reason',
            onChanged: (value) => _reason = value,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Save Incident Link'),
      ),
    ],
  );
}

class _HistoricalFindingDialog extends StatefulWidget {
  const _HistoricalFindingDialog({
    required this.terminalStatus,
    required this.onSave,
    required this.errorMessage,
  });

  final String terminalStatus;
  final Future<Map<String, dynamic>> Function(
    DisputeFindingOutcome outcome,
    String reason,
  )
  onSave;
  final String Function(Object error) errorMessage;

  @override
  State<_HistoricalFindingDialog> createState() =>
      _HistoricalFindingDialogState();
}

class _HistoricalFindingDialogState extends State<_HistoricalFindingDialog> {
  DisputeFindingOutcome? _outcome;
  String _reason = '';
  bool _busy = false;
  String? _error;

  Future<void> _confirmAndSave() async {
    if (_outcome == null || _reason.trim().isEmpty) {
      setState(() {
        _error = 'Select an outcome and provide an evidence-based reason.';
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm historical finding'),
        content: Text(
          'This writes a historical structured decision. The Dispute will remain ${widget.terminalStatus}, and Trust Score coverage will not be attested automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm classification'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSave(_outcome!, _reason.trim());
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review Historical Finding'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose the outcome supported by the reviewed evidence. A terminal status does not imply either party was at fault.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DisputeFindingOutcome>(
            initialValue: _outcome,
            decoration: const InputDecoration(labelText: 'Historical outcome'),
            items: [
              for (final value in DisputeFindingOutcome.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _outcome = value;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 12),
          _DialogTextField(
            enabled: !_busy,
            maxLines: 5,
            maxLength: 2000,
            labelText: 'Evidence-based reason',
            onChanged: (value) => _reason = value,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _confirmAndSave,
        child: Text(_busy ? 'Saving…' : 'Continue'),
      ),
    ],
  );
}

class _AddRelatedCaseDialog extends StatefulWidget {
  const _AddRelatedCaseDialog({
    required this.candidates,
    required this.onSave,
    required this.errorMessage,
  });

  final List<Map<String, dynamic>> candidates;
  final Future<String> Function(String incidentId, String reason) onSave;
  final String Function(Object error) errorMessage;

  @override
  State<_AddRelatedCaseDialog> createState() => _AddRelatedCaseDialogState();
}

class _AddRelatedCaseDialogState extends State<_AddRelatedCaseDialog> {
  String? _incidentId;
  String _reason = '';
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_incidentId == null || _reason.trim().isEmpty) {
      setState(() => _error = 'Select an Incident and provide a reason.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_incidentId!, _reason.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Related Case'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.candidates.isEmpty)
            const Text(
              'No authorized compatible Incidents are available. Related Cases require the same Worker and Company.',
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _incidentId,
              decoration: const InputDecoration(labelText: 'Related Incident'),
              items: [
                for (final candidate in widget.candidates)
                  DropdownMenuItem(
                    value: candidate['incident_id'] as String,
                    child: Text(
                      '${candidate['category']} · ${candidate['incident_id']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _incidentId = value),
            ),
          const SizedBox(height: 12),
          _DialogTextField(
            enabled: !_busy && widget.candidates.isNotEmpty,
            maxLines: 4,
            maxLength: 2000,
            labelText: 'Relationship reason',
            onChanged: (value) => _reason = value,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy || widget.candidates.isEmpty ? null : _save,
        child: Text(_busy ? 'Adding…' : 'Add Related Case'),
      ),
    ],
  );
}

class _RemoveRelatedCaseDialog extends StatefulWidget {
  const _RemoveRelatedCaseDialog({
    required this.incidentId,
    required this.onSave,
    required this.errorMessage,
  });

  final String incidentId;
  final Future<String> Function(String reason) onSave;
  final String Function(Object error) errorMessage;

  @override
  State<_RemoveRelatedCaseDialog> createState() =>
      _RemoveRelatedCaseDialogState();
}

class _RemoveRelatedCaseDialogState extends State<_RemoveRelatedCaseDialog> {
  String _reason = '';
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_reason.trim().isEmpty) {
      setState(() => _error = 'Provide a reason for removing this relation.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_reason.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Remove Related Case'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText('Incident ID: ${widget.incidentId}'),
          const SizedBox(height: 12),
          _DialogTextField(
            enabled: !_busy,
            maxLines: 4,
            maxLength: 2000,
            labelText: 'Removal reason',
            onChanged: (value) => _reason = value,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Removing…' : 'Remove'),
      ),
    ],
  );
}

class _DialogTextField extends StatefulWidget {
  const _DialogTextField({
    required this.enabled,
    required this.maxLines,
    required this.maxLength,
    required this.labelText,
    required this.onChanged,
  });

  final bool enabled;
  final int maxLines;
  final int maxLength;
  final String labelText;
  final ValueChanged<String> onChanged;

  @override
  State<_DialogTextField> createState() => _DialogTextFieldState();
}

class _DialogTextFieldState extends State<_DialogTextField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    enabled: widget.enabled,
    maxLines: widget.maxLines,
    maxLength: widget.maxLength,
    decoration: InputDecoration(labelText: widget.labelText),
    onChanged: widget.onChanged,
  );
}
