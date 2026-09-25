import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';

class MockDashboardRepository implements DashboardRepository {
  MockDashboardRepository({Dashboard? dashboard})
    : _dashboard = dashboard ?? MockData.dashboard;
  final Dashboard _dashboard;

  @override
  Future<Dashboard> getDashboard() async => _dashboard;
}
