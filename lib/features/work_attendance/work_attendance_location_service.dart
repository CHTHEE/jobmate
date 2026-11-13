import 'package:geolocator/geolocator.dart';

import 'work_attendance_models.dart';

/// Captures a fresh device location for a single attendance action.
/// Does not track location in the background or submit attendance.
class WorkAttendanceLocationService {
  Future<WorkAttendanceLocation> capture() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        return const WorkAttendanceLocation.unavailable();
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const WorkAttendanceLocation.denied();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      return WorkAttendanceLocation.granted(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // GPS can fail indoors, when disabled, or after a timeout.
      // The UI will offer Retry GPS or Continue without GPS.
      return const WorkAttendanceLocation.unavailable();
    }
  }
}
