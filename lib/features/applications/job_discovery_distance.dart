import 'dart:math' as math;

import '../jobs/workplace_coordinates.dart';

double? jobDiscoveryDistanceKm(
  WorkplaceCoordinates origin,
  WorkplaceCoordinates destination,
) {
  bool valid(WorkplaceCoordinates point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude.abs() <= 90 &&
      point.longitude.abs() <= 180;
  if (!valid(origin) || !valid(destination)) return null;

  double radians(double degrees) => degrees * math.pi / 180;
  final latitudeDelta = radians(destination.latitude - origin.latitude);
  final longitudeDelta = radians(destination.longitude - origin.longitude);
  final sinLat = math.sin(latitudeDelta / 2);
  final sinLon = math.sin(longitudeDelta / 2);
  final haversine =
      sinLat * sinLat +
      math.cos(radians(origin.latitude)) *
          math.cos(radians(destination.latitude)) *
          sinLon *
          sinLon;
  return 2 * 6371.0088 * math.asin(math.sqrt(haversine.clamp(0, 1)));
}
