import 'dart:async';

import 'package:jobmate/features/applications/job_application_repository.dart';
import 'package:jobmate/features/profile/resume_repository.dart';

class TestApplicationGateway implements JobApplicationGateway {
  @override
  String? actorId = 'seeker-a';
  String? currentActor = 'seeker-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  List<ResumeFile> files = [];
  Future<List<ResumeFile>> Function()? load;
  Future<String> Function()? send;
  int submissions = 0;
  String? sentJob, sentResume, sentNote;
  @override
  Stream<String?> get accountChanges => changes.stream;
  @override
  void checkSession() {
    if (currentActor == null || currentActor != actorId) {
      throw StateError('Account changed');
    }
  }

  void switchAccount(String? actor) {
    currentActor = actor;
    changes.add(actor);
  }

  @override
  Future<List<ResumeFile>> listResumes() => load?.call() ?? Future.value(files);
  @override
  Future<String> submit(
    String jobId, {
    String? resumeId,
    String? coverNote,
  }) async {
    checkSession();
    submissions++;
    sentJob = jobId;
    sentResume = resumeId;
    sentNote = coverNote;
    return send?.call() ?? '11111111-1111-4111-8111-111111111111';
  }
}
