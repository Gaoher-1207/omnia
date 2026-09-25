import 'package:omnia_ui/features/home/domain/dashboard.dart';

abstract interface class DashboardRepository {
  Future<Dashboard> getDashboard();
}
