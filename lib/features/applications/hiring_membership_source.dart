import 'package:supabase_flutter/supabase_flutter.dart';

import 'my_applications_repository.dart';
import 'hiring_membership_status.dart';

/// New compile-time release switch. Default OFF; not a backend readiness probe.
/// Enable only in an explicitly approved build after the coordinated DB release.
const hiringMembershipEnabled = bool.fromEnvironment(
  'JOBMATE_HIRING_MEMBERSHIP',
  defaultValue: false,
);

MyApplicationsSource createMyApplicationsSource(
  SupabaseClient client, {
  bool enableHiringMembership = hiringMembershipEnabled,
}) => enableHiringMembership
    ? HiringMembershipApplicationsSource.forApprovedBackend(client)
    : SupabaseMyApplicationsSource(client);

/// Client integration port, not a deployed RPC contract. An implementation must
/// perform acceptance and ordinary enrollment in ONE authorized server transaction,
/// with idempotent replay and no inactive/revoked membership reactivation. Never
/// implement this with a legacy acceptance followed by a membership insert.
/// The acknowledgement is text; status/history still come from fresh owned reads.
abstract interface class AtomicHiringMembershipGateway {
  String? get userId;
  Future<String> acceptOffer(String applicationId);
}

/// No remote call or optimistic enrollment when the server adapter is unavailable.
class UnavailableHiringMembershipGateway
    implements AtomicHiringMembershipGateway {
  const UnavailableHiringMembershipGateway();

  @override
  String? get userId => null;

  @override
  Future<String> acceptOffer(String applicationId) async {
    throw StateError('Hiring membership integration is unavailable.');
  }
}

/// Transport for the reviewed existing RPC signature, NOT a deployment probe.
/// Construct only after joint approval/deployment of atomic enrollment and its
/// compatibility changes. Nothing in this class establishes backend readiness.
/// Production composition intentionally continues to use the legacy source.
class SupabaseAtomicHiringMembershipGateway
    implements AtomicHiringMembershipGateway, HiringMembershipStatusSource {
  SupabaseAtomicHiringMembershipGateway.forApprovedBackend(this.client);

  final SupabaseClient client;

  @override
  Future<HiringMembershipSnapshot> loadMembership(String applicationId) async {
    final actor = userId;
    if (actor == null || applicationId.trim().isEmpty) {
      throw StateError('Sign in and refresh the application.');
    }
    final result = await client
        .rpc(
          'get_my_hiring_membership',
          params: {'p_application_id': applicationId},
        )
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
    if (userId != actor) {
      throw StateError('Your session changed.');
    }
    if (result is! Map) {
      throw const FormatException('Invalid membership result.');
    }
    return HiringMembershipSnapshot.fromJson(
      Map<String, dynamic>.from(result),
      applicationId: applicationId,
      userId: actor,
    );
  }

  @override
  String? get userId =>
      client.auth.currentSession == null ? null : client.auth.currentUser?.id;

  @override
  Future<String> acceptOffer(String applicationId) async {
    final actor = userId;
    if (actor == null || applicationId.trim().isEmpty) {
      throw StateError('Sign in and refresh the application before accepting.');
    }
    final result = await client
        .rpc(
          'respond_to_job_application',
          params: {
            'p_application_id': applicationId,
            'p_action': 'accept_offer',
          },
        )
        .retry(enabled: false, requestTimeout: const Duration(seconds: 30));
    if (userId != actor) {
      throw StateError('Your session changed. Refresh the application.');
    }
    if (result is! String) {
      throw const FormatException('Invalid application response.');
    }
    return result;
  }
}

/// Opt-in source for a future coordinated release. Existing production sources
/// are unchanged. Reads and non-accept actions use the existing contracts; offer
/// acceptance never falls back to the legacy source. No Supabase adapter is
/// selected by production until atomic backend behavior is approved/deployed.
class HiringMembershipApplicationsSource
    implements MyApplicationsSource, HiringMembershipStatusSource {
  HiringMembershipApplicationsSource(
    this.applications, {
    this.gateway = const UnavailableHiringMembershipGateway(),
  });

  /// Future activation point only: both paths share the same client/session.
  /// Never select this factory before the coordinated backend release is approved.
  factory HiringMembershipApplicationsSource.forApprovedBackend(
    SupabaseClient client,
  ) => HiringMembershipApplicationsSource(
    SupabaseMyApplicationsSource(client),
    gateway: SupabaseAtomicHiringMembershipGateway.forApprovedBackend(client),
  );

  final MyApplicationsSource applications;
  final AtomicHiringMembershipGateway gateway;
  bool _responding = false;

  @override
  Future<HiringMembershipSnapshot> loadMembership(String applicationId) async {
    final actor = userId;
    final reader = gateway;
    if (actor == null ||
        reader.userId != actor ||
        reader is! HiringMembershipStatusSource) {
      throw StateError('Hiring membership integration is unavailable.');
    }
    var changed = false;
    final subscription = accountChanges.listen((id) {
      if (id != actor) changed = true;
    });
    try {
      final result = await (reader as HiringMembershipStatusSource)
          .loadMembership(applicationId);
      if (changed || userId != actor || gateway.userId != actor) {
        throw StateError('Your session changed.');
      }
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  @override
  String? get userId => applications.userId;

  @override
  Stream<String?> get accountChanges => applications.accountChanges;

  @override
  Future<List<Map<String, dynamic>>> list() => applications.list();

  @override
  Future<List<Map<String, dynamic>>> history(String applicationId) =>
      applications.history(applicationId);

  @override
  Future<String> respond(String applicationId, String action) async {
    if (!ApplicationResponseAction.values.any((a) => a.wireName == action) ||
        applicationId.trim().isEmpty) {
      throw StateError('This application action is unavailable.');
    }
    if (_responding) {
      throw StateError('An application response is in progress.');
    }
    final actor = userId;
    if (actor == null) {
      throw StateError('Sign in to respond to this application.');
    }
    final accepting = action == ApplicationResponseAction.acceptOffer.wireName;
    if (accepting && (gateway.userId == null || gateway.userId != actor)) {
      throw StateError('Hiring membership integration is unavailable.');
    }
    _responding = true;
    var changed = false;
    final subscription = accountChanges.listen((id) {
      if (id != actor) changed = true;
    });
    try {
      final acknowledgement = accepting
          ? await gateway.acceptOffer(applicationId)
          : await applications.respond(applicationId, action);
      if (changed || userId != actor || accepting && gateway.userId != actor) {
        throw StateError('Your session changed. Refresh the application.');
      }
      return acknowledgement;
    } finally {
      await subscription.cancel();
      _responding = false;
    }
  }
}
