import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';

class DashboardRepository {
  DashboardRepository(this._api);
  final ApiClient _api;

  Future<Dashboard> load() async => Dashboard.fromJson(asMap(await _api.get('/dashboard')));
}
