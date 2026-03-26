import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bean_budget/core/database/tables.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/features/receipts/receipts_notifier.dart';

class ReceiptCropperWidget extends StatefulWidget {
  final ReceiptData item;
  final ReceiptsNotifier notifier;

  const ReceiptCropperWidget({
    super.key,
    required this.item,
    required this.notifier,
  });

  @override
  State<ReceiptCropperWidget> createState() => _ReceiptCropperWidgetState();
}

class _ReceiptCropperWidgetState extends State<ReceiptCropperWidget> {
  // Normalized coordinates (0.0 to 1.0)
  late Offset _tl;
  late Offset _tr;
  late Offset _br;
  late Offset _bl;

  int? _draggingCornerIndex; // 0=tl, 1=tr, 2=br, 3=bl

  // Hit testing tolerance
  static const double _touchSlop = 0.1;

  @override
  void initState() {
    super.initState();
    // Initialize points to the existing crop or to a default inner rect (10% inset)
    final existing = widget.item.receipt.cropPoints;
    if (existing != null) {
      _tl = Offset(existing.topLeft.x, existing.topLeft.y);
      _tr = Offset(existing.topRight.x, existing.topRight.y);
      _br = Offset(existing.bottomRight.x, existing.bottomRight.y);
      _bl = Offset(existing.bottomLeft.x, existing.bottomLeft.y);
    } else {
      _tl = const Offset(0.1, 0.1);
      _tr = const Offset(0.9, 0.1);
      _br = const Offset(0.9, 0.9);
      _bl = const Offset(0.1, 0.9);
    }
  }

  void _onPanUpdateDirect(DragUpdateDetails details, Size layoutSize) {
    if (_draggingCornerIndex == null) return;

    final delta = Offset(
      details.delta.dx / layoutSize.width,
      details.delta.dy / layoutSize.height,
    );

    setState(() {
      Offset oldPos;
      if (_draggingCornerIndex == 0) oldPos = _tl;
      else if (_draggingCornerIndex == 1) oldPos = _tr;
      else if (_draggingCornerIndex == 2) oldPos = _br;
      else oldPos = _bl;

      var newPos = oldPos + delta;
      newPos = Offset(newPos.dx.clamp(0.0, 1.0), newPos.dy.clamp(0.0, 1.0));

      if (_draggingCornerIndex == 0) _tl = newPos;
      else if (_draggingCornerIndex == 1) _tr = newPos;
      else if (_draggingCornerIndex == 2) _br = newPos;
      else if (_draggingCornerIndex == 3) _bl = newPos;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_draggingCornerIndex != null) {
      _saveCrop();
    }
    setState(() => _draggingCornerIndex = null);
  }

  Future<void> _saveCrop() async {
    final points = CropPoints(
      topLeft: Coordinate(x: _tl.dx, y: _tl.dy),
      topRight: Coordinate(x: _tr.dx, y: _tr.dy),
      bottomRight: Coordinate(x: _br.dx, y: _br.dy),
      bottomLeft: Coordinate(x: _bl.dx, y: _bl.dy),
    );

    await widget.notifier.saveCropPoints(widget.item.receipt.id, points);
  }

  Widget _buildHandle(int index, Offset normalizedPos, Size size) {
    const double touchRadius = 36.0;
    final pos = Offset(normalizedPos.dx * size.width, normalizedPos.dy * size.height);
    
    return Positioned(
      left: pos.dx - touchRadius,
      top: pos.dy - touchRadius,
      width: touchRadius * 2,
      height: touchRadius * 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => setState(() => _draggingCornerIndex = index),
        onPanUpdate: (d) => _onPanUpdateDirect(d, size),
        onPanEnd: _onPanEnd,
        onPanCancel: () => setState(() => _draggingCornerIndex = null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: InteractiveViewer(
          boundaryMargin: EdgeInsets.zero,
          minScale: 0.8,
          maxScale: 5.0,
          child: AspectRatio(
            aspectRatio: widget.item.image.width > 0 && widget.item.image.height > 0
                ? widget.item.image.width / widget.item.image.height
                : 0.7, // fallback
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Base image
                    Image.file(
                      File(widget.item.image.filePath),
                      fit: BoxFit.contain,
                    ),
                    // Custom Drawing layer for masks and handles
                    CustomPaint(
                      painter: _CropperPainter(
                        tl: _tl,
                        tr: _tr,
                        br: _br,
                        bl: _bl,
                        hasActiveDrag: _draggingCornerIndex != null,
                      ),
                    ),
                    // Invisible hit boxes for exactly the 4 corners
                    _buildHandle(0, _tl, size),
                    _buildHandle(1, _tr, size),
                    _buildHandle(2, _br, size),
                    _buildHandle(3, _bl, size),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CropperPainter extends CustomPainter {
  final Offset tl;
  final Offset tr;
  final Offset br;
  final Offset bl;
  final bool hasActiveDrag;

  _CropperPainter({
    required this.tl,
    required this.tr,
    required this.br,
    required this.bl,
    required this.hasActiveDrag,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Convert normalized coords to pixel offsets
    final pTl = Offset(tl.dx * size.width, tl.dy * size.height);
    final pTr = Offset(tr.dx * size.width, tr.dy * size.height);
    final pBr = Offset(br.dx * size.width, br.dy * size.height);
    final pBl = Offset(bl.dx * size.width, bl.dy * size.height);

    // Dark mask over the unselected part
    final fullRect = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropQuad = Path()
      ..moveTo(pTl.dx, pTl.dy)
      ..lineTo(pTr.dx, pTr.dy)
      ..lineTo(pBr.dx, pBr.dy)
      ..lineTo(pBl.dx, pBl.dy)
      ..close();

    final maskPath = Path.combine(PathOperation.difference, fullRect, cropQuad);
    
    // Draw outer dark mask
    canvas.drawPath(
      maskPath,
      Paint()
        ..color = Colors.black.withOpacity(0.7)
        ..style = PaintingStyle.fill,
    );

    // Draw lines connecting the 4 corners
    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(cropQuad, linePaint);

    // Draw handles
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handleOutline = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final radius = hasActiveDrag ? 14.0 : 10.0;

    for (var pt in [pTl, pTr, pBr, pBl]) {
      canvas.drawCircle(pt, radius, handlePaint);
      canvas.drawCircle(pt, radius, handleOutline);
      // Small inner dot
      canvas.drawCircle(pt, 3.0, Paint()..color = AppColors.primary);
    }
  }

  @override
  bool shouldRepaint(covariant _CropperPainter oldDelegate) {
    return tl != oldDelegate.tl ||
           tr != oldDelegate.tr ||
           br != oldDelegate.br ||
           bl != oldDelegate.bl ||
           hasActiveDrag != oldDelegate.hasActiveDrag;
  }
}
