/// Local presentation rules. The backend must independently enforce every rule.
enum DisputeCategory { recruitment, workCompletion, payment }

enum DisputeStatus {
  open,
  investigating,
  pendingInformation,
  resolved,
  rejected,
}

enum DisputeAction { investigate, requestInformation, resume, resolve, reject }

abstract final class DisputeWorkflow {
  static bool canApply(DisputeStatus status, DisputeAction action) =>
      switch ((status, action)) {
        (DisputeStatus.open, DisputeAction.investigate) => true,
        (DisputeStatus.investigating, DisputeAction.requestInformation) => true,
        (DisputeStatus.pendingInformation, DisputeAction.resume) => true,
        (DisputeStatus.investigating, DisputeAction.resolve) => true,
        (DisputeStatus.investigating, DisputeAction.reject) => true,
        _ => false,
      };

  static DisputeStatus next(DisputeStatus status, DisputeAction action) {
    if (!canApply(status, action)) {
      throw StateError('This dispute action is not available.');
    }
    return switch (action) {
      DisputeAction.investigate ||
      DisputeAction.resume => DisputeStatus.investigating,
      DisputeAction.requestInformation => DisputeStatus.pendingInformation,
      DisputeAction.resolve => DisputeStatus.resolved,
      DisputeAction.reject => DisputeStatus.rejected,
    };
  }

  static bool requiresReason(DisputeAction action) => switch (action) {
    DisputeAction.requestInformation ||
    DisputeAction.resolve ||
    DisputeAction.reject => true,
    _ => false,
  };

  static bool validReason(DisputeAction action, String reason) {
    final trimmed = reason.trim();
    return trimmed.runes.length <= 2000 &&
        (!requiresReason(action) || trimmed.isNotEmpty);
  }
}
