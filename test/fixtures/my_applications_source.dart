import 'dart:async';

import 'package:jobmate/features/applications/my_applications_repository.dart';

class TestMyApplicationsSource
    implements MyApplicationsSource, ExactVersionCompensationOfferSource {
  String? actor = 'seeker-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  List<Map<String, dynamic>> rows = [];
  Future<List<Map<String, dynamic>>> Function()? fetch;
  int calls = 0;
  final historyCalls = <String>[];
  final responses = <(String, String)>[];
  final offerReads = <String>[];
  final offerAcceptances = <(String, String, int)>[];
  Map<String, dynamic>? offer;
  Future<Map<String, dynamic>?> Function(String)? fetchOffer;
  Future<void> Function(String, String, int)? sendOfferAcceptance;
  Future<String> Function(String, String)? sendResponse;
  @override
  Future<String> respond(String applicationId, String action) {
    responses.add((applicationId, action));
    return sendResponse!(applicationId, action);
  }

  @override
  Future<Map<String, dynamic>?> currentCompensationOffer(String id) {
    offerReads.add(id);
    return fetchOffer?.call(id) ?? Future.value(offer);
  }

  @override
  Future<void> acceptCompensationOffer(
    String applicationId,
    String offerId,
    int offerVersion,
  ) async {
    offerAcceptances.add((applicationId, offerId, offerVersion));
    await sendOfferAcceptance?.call(applicationId, offerId, offerVersion);
  }

  List<Map<String, dynamic>> historyRows = [];
  Future<List<Map<String, dynamic>>> Function(String)? fetchHistory;
  @override
  Future<List<Map<String, dynamic>>> history(String applicationId) {
    historyCalls.add(applicationId);
    return fetchHistory?.call(applicationId) ?? Future.value(historyRows);
  }

  @override
  String? get userId => actor;
  @override
  Stream<String?> get accountChanges => changes.stream;
  @override
  Future<List<Map<String, dynamic>>> list() {
    calls++;
    return fetch?.call() ?? Future.value(rows);
  }

  void switchAccount(String? value) {
    actor = value;
    changes.add(value);
  }
}

Map<String, dynamic> applicationRow(String id, {String status = 'submitted'}) =>
    {
      'application_id': id,
      'job_id': 'real-job-id',
      'job_title': 'Part-Time Cafe Crew',
      'company_name': 'ABC Company',
      'resume_id': null,
      'cover_note': null,
      'status': status,
      'applied_at': '2026-11-04T10:11:37.58546Z',
      'updated_at': '2026-11-04T10:11:37.58546Z',
      'withdrawn_at': null,
    };

Map<String, dynamic> historyRow(String id, {String status = 'submitted'}) => {
  'history_id': id,
  'previous_status': null,
  'new_status': status,
  'changed_by': 'seeker-a',
  'changed_by_name': 'Applicant',
  'note': null,
  'changed_at': '2026-11-04T10:11:37.58546Z',
};
