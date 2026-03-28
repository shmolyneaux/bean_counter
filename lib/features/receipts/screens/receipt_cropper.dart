import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bean_budget/core/database/tables.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/features/receipts/receipts_notifier.dart';

class ReceiptCropperWidget extends StatefulWidget {
  final ReceiptData item;
  final ReceiptsNotifier notifier;
  /// Called after saving, e.g. to exit adjust-crop mode. Null for raw receipts.
  final VoidCallback? onAccepted;

  const ReceiptCropperWidget({
    super.key,
    required this.item,
    required this.notifier,
    this.onAccepted,
  });

  @override
  State<ReceiptCropperWidget> createState() => _ReceiptCropperWidgetState();
}

class _ReceiptCropperWidgetState extends State<ReceiptCropperWidget> {
  late Offset _tl, _tr, _br, _bl;
  int? _draggingCornerIndex;
  int? _hoveredCornerIndex;
  bool _detecting = false;
  final _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    final existing = widget.item.receipt.cropPoints;
    if (existing != null) {
      _tl = Offset(existing.topLeft.x, existing.topLeft.y);
      _tr = Offset(existing.topRight.x, existing.topRight.y);
      _br = Offset(existing.bottomRight.x, existing.bottomRight.y);
      _bl = Offset(existing.bottomLeft.x, existing.bottomLeft.y);
    } else {
      // Default wide box while detection runs
      _tl = const Offset(0.1, 0.1);
      _tr = const Offset(0.9, 0.1);
      _br = const Offset(0.9, 0.9);
      _bl = const Offset(0.1, 0.9);
      _runAutoDetect();
    }
  }

  Future<void> _runAutoDetect() async {
    setState(() => _detecting = true);
    final detected = await widget.notifier.detectReceiptBbox(widget.item.image.filePath);
    if (!mounted) return;
    setState(() {
      _detecting = false;
      if (detected != null) {
        _tl = Offset(detected.topLeft.x, detected.topLeft.y);
        _tr = Offset(detected.topRight.x, detected.topRight.y);
        _br = Offset(detected.bottomRight.x, detected.bottomRight.y);
        _bl = Offset(detected.bottomLeft.x, detected.bottomLeft.y);
      }
    });
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size layoutSize) {
    if (_draggingCornerIndex == null) return;
    final delta = Offset(
      details.delta.dx / layoutSize.width,
      details.delta.dy / layoutSize.height,
    );
    setState(() {
      Offset base;
      if (_draggingCornerIndex == 0) base = _tl;
      else if (_draggingCornerIndex == 1) base = _tr;
      else if (_draggingCornerIndex == 2) base = _br;
      else base = _bl;

      final clamped = Offset(
        (base.dx + delta.dx).clamp(0.0, 1.0),
        (base.dy + delta.dy).clamp(0.0, 1.0),
      );

      if (_draggingCornerIndex == 0) _tl = clamped;
      else if (_draggingCornerIndex == 1) _tr = clamped;
      else if (_draggingCornerIndex == 2) _br = clamped;
      else if (_draggingCornerIndex == 3) _bl = clamped;
    });
  }

  void _onPanEnd(DragEndDetails _) {
    // Does NOT auto-save — user must press Accept Crop.
    setState(() => _draggingCornerIndex = null);
  }

  Future<void> _acceptCrop() async {
    await widget.notifier.saveCropPoints(
      widget.item.receipt.id,
      CropPoints(
        topLeft: Coordinate(x: _tl.dx, y: _tl.dy),
        topRight: Coordinate(x: _tr.dx, y: _tr.dy),
        bottomRight: Coordinate(x: _br.dx, y: _br.dy),
        bottomLeft: Coordinate(x: _bl.dx, y: _bl.dy),
      ),
    );
    widget.onAccepted?.call();
  }

  Widget _buildHandle(int index, Offset normalizedPos, Size size, double scale) {
    const double baseHitRadius = 28.0;
    final hitRadius = baseHitRadius / scale;
    final pos = Offset(normalizedPos.dx * size.width, normalizedPos.dy * size.height);

    return Positioned(
      left: pos.dx - hitRadius,
      top: pos.dy - hitRadius,
      width: hitRadius * 2,
      height: hitRadius * 2,
      child: MouseRegion(
        cursor: _draggingCornerIndex == index
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hoveredCornerIndex = index),
        onExit: (_) => setState(() {
          if (_hoveredCornerIndex == index) _hoveredCornerIndex = null;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => setState(() => _draggingCornerIndex = index),
          onPanUpdate: (d) => _onPanUpdate(d, size),
          onPanEnd: _onPanEnd,
          onPanCancel: () => setState(() => _draggingCornerIndex = null),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: InteractiveViewer(
              transformationController: _transformCtrl,
              boundaryMargin: EdgeInsets.zero,
              minScale: 0.8,
              maxScale: 5.0,
              child: AspectRatio(
                aspectRatio: widget.item.image.width > 0 && widget.item.image.height > 0
                    ? widget.item.image.width / widget.item.image.height
                    : 0.7,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, constraints.maxHeight);
                    return AnimatedBuilder(
                      animation: _transformCtrl,
                      builder: (context, child) {
                        final scale = _transformCtrl.value.getMaxScaleOnAxis();
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            child!,
                            CustomPaint(
                              painter: _CropperPainter(
                                tl: _tl, tr: _tr, br: _br, bl: _bl,
                                draggingCornerIndex: _draggingCornerIndex,
                                hoveredCornerIndex: _hoveredCornerIndex,
                                scale: scale,
                              ),
                            ),
                            _buildHandle(0, _tl, size, scale),
                            _buildHandle(1, _tr, size, scale),
                            _buildHandle(2, _br, size, scale),
                            _buildHandle(3, _bl, size, scale),
                          ],
                        );
                      },
                      child: Image.file(
                        File(widget.item.image.filePath),
                        fit: BoxFit.fill,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        // Accept button lives OUTSIDE the InteractiveViewer so it never scales.
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton.extended(
            onPressed: _acceptCrop,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Accept Crop'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
        if (_detecting)
          Positioned(
            bottom: 32,
            left: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
                SizedBox(width: 8),
                Text('Detecting receipt…', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }
}

class _CropperPainter extends CustomPainter {
  final Offset tl, tr, br, bl;
  final int? draggingCornerIndex;
  final int? hoveredCornerIndex;
  final double scale;

  _CropperPainter({
    required this.tl, required this.tr,
    required this.br, required this.bl,
    required this.draggingCornerIndex,
    required this.hoveredCornerIndex,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pTl = Offset(tl.dx * size.width, tl.dy * size.height);
    final pTr = Offset(tr.dx * size.width, tr.dy * size.height);
    final pBr = Offset(br.dx * size.width, br.dy * size.height);
    final pBl = Offset(bl.dx * size.width, bl.dy * size.height);

    // Dark mask outside the crop quad.
    final fullRect = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropQuad = Path()
      ..moveTo(pTl.dx, pTl.dy)
      ..lineTo(pTr.dx, pTr.dy)
      ..lineTo(pBr.dx, pBr.dy)
      ..lineTo(pBl.dx, pBl.dy)
      ..close();
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullRect, cropQuad),
      Paint()..color = Colors.black.withOpacity(0.65)..style = PaintingStyle.fill,
    );

    // Crop border — scale-invariant stroke width.
    canvas.drawPath(
      cropQuad,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.0 / scale
        ..style = PaintingStyle.stroke,
    );

    // Handles — all dimensions divided by scale so they appear the same size at any zoom.
    final baseRadius = 10.0 / scale;
    final strokeW = 2.0 / scale;
    final points = [pTl, pTr, pBr, pBl];

    for (int i = 0; i < 4; i++) {
      final pt = points[i];
      final isDragging = draggingCornerIndex == i;
      final isHovered = hoveredCornerIndex == i && !isDragging;
      final radius = (isDragging || isHovered) ? baseRadius * 1.35 : baseRadius;

      if (isDragging) {
        // Transparent center: outline-only so you can see exactly where the corner is.
        canvas.drawCircle(pt, radius, Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..strokeWidth = strokeW * 1.5
          ..style = PaintingStyle.stroke);
        canvas.drawCircle(pt, radius + 4.0 / scale, Paint()
          ..color = AppColors.primary.withOpacity(0.6)
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke);
      } else {
        // Normal / hovered: filled white circle with colored border.
        canvas.drawCircle(pt, radius, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill);
        canvas.drawCircle(pt, radius, Paint()
          ..color = isHovered ? Colors.lightBlue.shade300 : AppColors.primary
          ..strokeWidth = isHovered ? strokeW * 1.5 : strokeW
          ..style = PaintingStyle.stroke);
        // Centre dot.
        canvas.drawCircle(pt, 2.5 / scale, Paint()..color = AppColors.primary);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropperPainter old) =>
      tl != old.tl || tr != old.tr || br != old.br || bl != old.bl ||
      draggingCornerIndex != old.draggingCornerIndex ||
      hoveredCornerIndex != old.hoveredCornerIndex ||
      scale != old.scale;
}
