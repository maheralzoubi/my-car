import 'data/repositories/mock_roadside_repository.dart';
import 'data/repositories/roadside_repository.dart';

/// Singleton access point for the roadside repository.
/// Swap [_repo] with a real backend implementation when ready.
class RoadsideService {
  RoadsideService._();
  static final RoadsideService instance = RoadsideService._();

  static RoadsideRepository _repo = MockRoadsideRepository();

  RoadsideRepository get repository => _repo;

  // ignore: use_setters_to_change_properties
  static void setRepository(RoadsideRepository repo) => _repo = repo;
}
