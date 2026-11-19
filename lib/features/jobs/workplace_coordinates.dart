typedef WorkplaceCoordinates = ({double latitude, double longitude});

WorkplaceCoordinates? workplaceCoordinates(
  Object? latitude,
  Object? longitude,
) {
  if (latitude is! num ||
      longitude is! num ||
      !latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    return null;
  }
  return (
    latitude: (latitude * 1000000).round() / 1000000,
    longitude: (longitude * 1000000).round() / 1000000,
  );
}

const confirmWorkplaceMessage =
    'Confirm the workplace location on the map before saving this published job.';

const workplaceRequiredForPublication =
    'Confirm the workplace location on the map before publishing.';
