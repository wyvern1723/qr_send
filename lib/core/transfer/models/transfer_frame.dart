import 'transfer_chunk.dart';
import 'transfer_session.dart';

enum TransferFrameType {
  header('H'),
  data('D'),
  end('E');

  const TransferFrameType(this.code);

  final String code;

  static TransferFrameType fromCode(String code) {
    return TransferFrameType.values.firstWhere(
      (value) => value.code == code,
      orElse: () => throw const FormatException('Unknown frame type'),
    );
  }
}

class TransferFrame {
  const TransferFrame.header({
    required this.session,
  })  : type = TransferFrameType.header,
        chunk = null;

  const TransferFrame.data({
    required this.session,
    required this.chunk,
  }) : type = TransferFrameType.data;

  const TransferFrame.end({
    required this.session,
  })  : type = TransferFrameType.end,
        chunk = null;

  final TransferFrameType type;
  final TransferSession session;
  final TransferChunk? chunk;
}
