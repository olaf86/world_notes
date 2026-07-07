enum NoteVisitorSort { latest, visitCount }

class NoteVisitor {
  final String userId;
  final String? displayName;
  final String? photoUrl;
  final DateTime firstVisitedAt;
  final DateTime lastVisitedAt;
  final int visitCount;
  final bool isMaintainer;

  const NoteVisitor({
    required this.userId,
    this.displayName,
    this.photoUrl,
    required this.firstVisitedAt,
    required this.lastVisitedAt,
    required this.visitCount,
    this.isMaintainer = false,
  });

  String get label {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? userId : name;
  }
}
