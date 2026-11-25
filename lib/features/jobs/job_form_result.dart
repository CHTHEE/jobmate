enum JobFormChange { created, updated, closed }

/// A successful editor return carries the row confirmed by the save RPC.
/// Closing without saving returns null.
class JobFormResult {
  JobFormResult(this.change, Map<String, dynamic> job)
    : job = Map.unmodifiable(job);

  final JobFormChange change;
  final Map<String, dynamic> job;
}
