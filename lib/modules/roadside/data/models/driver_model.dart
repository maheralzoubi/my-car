class DriverModel {
  final String id;
  final String name;
  final String phone;
  final double rating;
  final int totalJobs;
  final String vehicleType;
  final String vehiclePlate;
  final String avatarInitials;
  final double distanceKm;

  const DriverModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.rating,
    required this.totalJobs,
    required this.vehicleType,
    required this.vehiclePlate,
    required this.avatarInitials,
    required this.distanceKm,
  });

  static const List<DriverModel> mockDrivers = [
    DriverModel(
      id: 'd1',
      name: 'Ahmed Al-Rashidi',
      phone: '+966 50 123 4567',
      rating: 4.9,
      totalJobs: 1243,
      vehicleType: 'Heavy Tow Truck',
      vehiclePlate: 'ABC 1234',
      avatarInitials: 'AA',
      distanceKm: 1.8,
    ),
    DriverModel(
      id: 'd2',
      name: 'Mohammed Hassan',
      phone: '+966 55 987 6543',
      rating: 4.7,
      totalJobs: 876,
      vehicleType: 'Flatbed Carrier',
      vehiclePlate: 'XYZ 5678',
      avatarInitials: 'MH',
      distanceKm: 2.3,
    ),
    DriverModel(
      id: 'd3',
      name: 'Khalid Al-Otaibi',
      phone: '+966 56 456 7890',
      rating: 4.8,
      totalJobs: 2108,
      vehicleType: 'Service Truck',
      vehiclePlate: 'DEF 9012',
      avatarInitials: 'KO',
      distanceKm: 1.2,
    ),
  ];
}
