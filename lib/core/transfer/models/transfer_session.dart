class TransferSession {
  const TransferSession({
    required this.sessionId,
    required this.fileName,
    required this.fileSize,
    required this.chunkSize,
    required this.totalChunks,
    required this.fileSha256,
    this.mimeType,
  });

  final String sessionId;
  final String fileName;
  final int fileSize;
  final int chunkSize;
  final int totalChunks;
  final String fileSha256;
  final String? mimeType;

  double get progressUnit => totalChunks == 0 ? 0 : 1 / totalChunks;

  TransferSession copyWith({
    String? sessionId,
    String? fileName,
    int? fileSize,
    int? chunkSize,
    int? totalChunks,
    String? fileSha256,
    String? mimeType,
  }) {
    return TransferSession(
      sessionId: sessionId ?? this.sessionId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      chunkSize: chunkSize ?? this.chunkSize,
      totalChunks: totalChunks ?? this.totalChunks,
      fileSha256: fileSha256 ?? this.fileSha256,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}
