import 'dart:math' as math;

import '../jobs/workplace_coordinates.dart';
import 'nearby_job_results.dart';

Map<String, dynamic> nearbyJobMarkers(List<NearbyJobResult> results) => {
  'type': 'FeatureCollection',
  'features': [
    for (final result in results)
      if (result.job.workplace case final workplace?)
        {
          'type': 'Feature',
          'id': result.job.id,
          'properties': {'jobId': result.job.id},
          'geometry': {
            'type': 'Point',
            'coordinates': [workplace.longitude, workplace.latitude],
          },
        },
  ],
};

List<List<double>> nearbyRadiusRing(WorkplaceCoordinates origin, int radiusKm) {
  const steps = 96;
  const radians = math.pi / 180;
  final angularDistance = radiusKm / 6371.0088;
  final latitude = origin.latitude * radians;
  final ring = [
    for (var i = 0; i < steps; i++)
      _radiusPoint(
        origin.longitude,
        latitude,
        angularDistance,
        -i * 2 * math.pi / steps,
      ),
  ];
  return [...ring, ring.first];
}

List<double> _radiusPoint(
  double longitude,
  double latitude,
  double distance,
  double bearing,
) {
  final lat = math.asin(
    math.sin(latitude) * math.cos(distance) +
        math.cos(latitude) * math.sin(distance) * math.cos(bearing),
  );
  final deltaLon = math.atan2(
    math.sin(bearing) * math.sin(distance) * math.cos(latitude),
    math.cos(distance) - math.sin(latitude) * math.sin(lat),
  );
  const degrees = 180 / math.pi;
  return [longitude + deltaLon * degrees, lat * degrees];
}
