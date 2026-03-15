import 'package:flutter/material.dart';

class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({
    super.key,
    required this.borderColor,
    this.borderWidth = 4,
    this.animationDuration = const Duration(milliseconds: 1500),
  });

  final Color borderColor;
  final double borderWidth;
  final Duration animationDuration;

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  static const double _cutoutSize = 250;

  late final AnimationController _animationController;
  late final Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cutoutLeft = (size.width - _cutoutSize) / 2;
    final cutoutTop = (size.height - _cutoutSize) / 2 - 50;

    return IgnorePointer(
      child: Stack(
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.6),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Positioned(
                  left: cutoutLeft,
                  top: cutoutTop,
                  child: Container(
                    width: _cutoutSize,
                    height: _cutoutSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: cutoutLeft,
            top: cutoutTop,
            child: Container(
              width: _cutoutSize,
              height: _cutoutSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.borderColor,
                  width: widget.borderWidth,
                ),
              ),
            ),
          ),
          Positioned(
            left: cutoutLeft,
            top: cutoutTop,
            child: AnimatedBuilder(
              animation: _scanLineAnimation,
              builder: (context, _) {
                return ClipRect(
                  child: CustomPaint(
                    size: const Size(_cutoutSize, _cutoutSize),
                    painter: _ScanLinePainter(
                      progress: _scanLineAnimation.value,
                      color: widget.borderColor,
                    ),
                  ),
                );
              },
            ),
          ),
          _buildCorner(left: cutoutLeft, top: cutoutTop, isTopLeft: true),
          _buildCorner(
            left: cutoutLeft + _cutoutSize,
            top: cutoutTop,
            isTopRight: true,
          ),
          _buildCorner(
            left: cutoutLeft,
            top: cutoutTop + _cutoutSize,
            isBottomLeft: true,
          ),
          _buildCorner(
            left: cutoutLeft + _cutoutSize,
            top: cutoutTop + _cutoutSize,
            isBottomRight: true,
          ),
          Positioned(
            top: cutoutTop + _cutoutSize + 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                const Text(
                  'Align the QR code inside the frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Keep the sender screen steady, bright, and as stable as possible.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: const [
                _OverlayTip(
                  text: 'Keep steady',
                  icon: Icons.stay_current_portrait,
                ),
                _OverlayTip(
                  text: 'Increase brightness',
                  icon: Icons.brightness_6,
                ),
                _OverlayTip(text: 'Avoid glare', icon: Icons.flash_off),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner({
    required double left,
    required double top,
    bool isTopLeft = false,
    bool isTopRight = false,
    bool isBottomLeft = false,
    bool isBottomRight = false,
  }) {
    const cornerSize = 30.0;
    const cornerWidth = 3.0;

    return Positioned(
      left: isTopLeft || isBottomLeft ? left : left - cornerSize,
      top: isTopLeft || isTopRight ? top : top - cornerSize,
      child: CustomPaint(
        size: const Size(cornerSize, cornerSize),
        painter: _CornerPainter(
          color: widget.borderColor,
          width: cornerWidth,
          isTopLeft: isTopLeft,
          isTopRight: isTopRight,
          isBottomLeft: isBottomLeft,
          isBottomRight: isBottomRight,
        ),
      ),
    );
  }
}

class _OverlayTip extends StatelessWidget {
  const _OverlayTip({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  _ScanLinePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, size.height * progress - 2, size.width, 4);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: [Colors.transparent, color, Colors.transparent],
        stops: const [0, 0.5, 1],
      ).createShader(rect);

    canvas.drawRect(rect, paint);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawRect(
      Rect.fromLTWH(0, size.height * progress - 4, size.width, 8),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.color,
    required this.width,
    this.isTopLeft = false,
    this.isTopRight = false,
    this.isBottomLeft = false,
    this.isBottomRight = false,
  });

  final Color color;
  final double width;
  final bool isTopLeft;
  final bool isTopRight;
  final bool isBottomLeft;
  final bool isBottomRight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    const lineLength = 20.0;

    if (isTopLeft) {
      canvas.drawLine(
        Offset(0, width / 2),
        Offset(lineLength, width / 2),
        paint,
      );
      canvas.drawLine(
        Offset(width / 2, 0),
        Offset(width / 2, lineLength),
        paint,
      );
    }

    if (isTopRight) {
      canvas.drawLine(
        Offset(size.width, width / 2),
        Offset(size.width - lineLength, width / 2),
        paint,
      );
      canvas.drawLine(
        Offset(size.width - width / 2, 0),
        Offset(size.width - width / 2, lineLength),
        paint,
      );
    }

    if (isBottomLeft) {
      canvas.drawLine(
        Offset(0, size.height - width / 2),
        Offset(lineLength, size.height - width / 2),
        paint,
      );
      canvas.drawLine(
        Offset(width / 2, size.height),
        Offset(width / 2, size.height - lineLength),
        paint,
      );
    }

    if (isBottomRight) {
      canvas.drawLine(
        Offset(size.width, size.height - width / 2),
        Offset(size.width - lineLength, size.height - width / 2),
        paint,
      );
      canvas.drawLine(
        Offset(size.width - width / 2, size.height),
        Offset(size.width - width / 2, size.height - lineLength),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.width != width ||
        oldDelegate.isTopLeft != isTopLeft ||
        oldDelegate.isTopRight != isTopRight ||
        oldDelegate.isBottomLeft != isBottomLeft ||
        oldDelegate.isBottomRight != isBottomRight;
  }
}
