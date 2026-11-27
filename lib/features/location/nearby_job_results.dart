import '../applications/job_discovery_distance.dart';
import '../applications/module2_repository.dart';
import '../jobs/workplace_coordinates.dart';

typedef NearbyJobResult = ({BrowseJob job, double distanceKm});

List<NearbyJobResult> nearbyJobResults(
  Iterable<BrowseJob> publishedJobs, {
  required WorkplaceCoordinates origin,
  required num radiusKm,
  String employmentType = '',
  DateTime? now,
}) {
  final results = <NearbyJobResult>[];
  final asOf = now ?? DateTime.now();
  for (final job in publishedJobs) {
    final workplace = job.workplace;
    final arrangement = job.text('work_arrangement');
    if (job.unavailable(asOf) != null ||
        (arrangement != 'on_site' && arrangement != 'hybrid') ||
        workplace == null ||
        (employmentType.isNotEmpty &&
            job.text('employment_type') != employmentType)) {
      continue;
    }
    final distance = jobDiscoveryDistanceKm(origin, workplace);
    if (distance != null && distance <= radiusKm) {
      results.add((job: job, distanceKm: distance));
    }
  }
  return results..sort((a, b) {
    final byDistance = a.distanceKm.compareTo(b.distanceKm);
    return byDistance == 0 ? a.job.id.compareTo(b.job.id) : byDistance;
  });
}
