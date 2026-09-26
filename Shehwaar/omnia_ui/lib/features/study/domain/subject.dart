/// A subject the user studies, e.g. "DBMS". Names are unique per user.
class Subject {
  const Subject({required this.id, required this.name});
  final String id, name;
}
