import 'package:omnia_ui/features/study/domain/study_session.dart';

/// The mock-mode demo revision session. The backend has no equivalent
/// (its study sessions are logged minutes), so this stays in memory.
abstract interface class RevisionRepository {
  Future<List<StudySession>> getSessions();
  Future<StudySession> getSession(String id);
  Future<StudySession> updateSession(StudySession session);
}
