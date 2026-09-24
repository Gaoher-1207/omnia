enum RepositoryError { notFound, duplicateId, invalidReference }

class RepositoryException implements Exception {
  const RepositoryException(this.code, this.id);
  final RepositoryError code;
  final String id;

  @override
  String toString() => 'RepositoryException(${code.name}, $id)';
}
