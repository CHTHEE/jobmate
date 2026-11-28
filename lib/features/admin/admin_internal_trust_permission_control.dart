import 'package:material_ui/material_ui.dart';

/// A presentation-only control. Its value must come from an authorized backend
/// projection; a missing value is deliberately not treated as false.
class AdminInternalTrustPermissionControl extends StatelessWidget {
  const AdminInternalTrustPermissionControl({
    super.key,
    required this.featureEnabled,
    required this.isAuthorizedSuperadmin,
    required this.isCurrentAdmin,
    required this.isTargetActive,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final bool featureEnabled;
  final bool isAuthorizedSuperadmin;
  final bool isCurrentAdmin;
  final bool isTargetActive;

  /// Null means the authorized server projection did not provide a valid state.
  final bool? value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!featureEnabled || !isAuthorizedSuperadmin) {
      return const SizedBox.shrink();
    }

    final stateAvailable = value != null;
    final enabled =
        stateAvailable && isTargetActive && !isCurrentAdmin && !busy;
    final subtitle = !stateAvailable
        ? 'Permission state is unavailable from the authorized Admin list projection.'
        : isCurrentAdmin
        ? 'You cannot change your own Internal Trust access.'
        : !isTargetActive
        ? 'Only active administrators can receive this permission.'
        : 'Allows this administrator to view provisional Job Seeker Internal Trust Scores.';

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('View Internal Trust Scores'),
      subtitle: Text(subtitle),
      value: value ?? false,
      onChanged: enabled ? onChanged : null,
    );
  }
}
