enum ContentReportTarget {
  message,
  note;

  String toJson() => name;
}

enum ReportReasonCode {
  spam,
  harassment,
  sexual,
  illegal,
  other;

  String toJson() => name;
}
