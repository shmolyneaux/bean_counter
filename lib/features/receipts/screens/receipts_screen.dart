import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:bean_budget/core/database/tables.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/utils/perspective_math.dart';
import 'package:bean_budget/features/receipts/receipts_notifier.dart';
import 'package:bean_budget/features/receipts/screens/receipt_cropper.dart';
import 'package:bean_budget/features/receipts/screens/receipt_verifier.dart';

class ReceiptsScreen extends StatefulWidget {
  final ReceiptsNotifier notifier;

  const ReceiptsScreen({super.key, required this.notifier});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  bool _isDragging = false;
  String? _selectedReceiptId;
  bool _isAdjustingCrop = false;
  List<OcrBox>? _ocrBoxes;
  Size? _ocrSize;

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onNotifierChanged);
    if (widget.notifier.receipts.isEmpty && !widget.notifier.isLoading) {
      widget.notifier.load();
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() {
    if (mounted) {
      // Validate selection
      if (_selectedReceiptId != null) {
        final stillExists = widget.notifier.receipts.any((r) => r.receipt.id == _selectedReceiptId);
        if (!stillExists) _selectedReceiptId = null;
      }
      setState(() {});
    }
  }

  void _onOcrComplete(String receiptId, List<OcrBox>? boxes, Size? size) {
    if (mounted && receiptId == _selectedReceiptId) {
      setState(() {
        _ocrBoxes = boxes;
        _ocrSize = size;
      });
    }
  }

  Future<void> _copyWord(String word) async {
    await Clipboard.setData(ClipboardData(text: word));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied: "$word"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildWordBox(OcrBox box) {
    final conf = box.confidence;
    final color = conf >= 80
        ? Colors.green
        : conf >= 50
            ? Colors.orange
            : Colors.red;

    return Tooltip(
      richMessage: TextSpan(children: [
        TextSpan(
          text: '"${box.word}"\n',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: 'Confidence: ${conf.toStringAsFixed(1)}%\n'),
        TextSpan(
          text: 'Block ${box.blockNum}  Para ${box.parNum}  '
              'Line ${box.lineNum}  Word ${box.wordNum}',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ]),
      child: GestureDetector(
        onTap: () => _copyWord(box.word),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.8), width: 1),
            color: color.withOpacity(0.08),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'images',
      extensions: <String>['jpg', 'jpeg', 'png', 'heic', 'heif'],
    );
    final List<XFile> files = await openFiles(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (files.isNotEmpty) {
      await widget.notifier.importFiles(files);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) => setState(() => _isDragging = true),
      onDragExited: (details) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        await widget.notifier.importFiles(details.files);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Receipts'),
          actions: [
            if (widget.notifier.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Import'),
              onPressed: _pickFiles,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            _build3PaneLayout(widget.notifier),
            if (_isDragging)
              Container(
                color: AppColors.primary.withAlpha(50),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.background.withAlpha(200),
                          blurRadius: 16,
                          spreadRadius: 4,
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.file_upload_rounded, size: 60, color: AppColors.primary),
                        const SizedBox(height: 16),
                        const Text(
                          'Drop images to import',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _build3PaneLayout(ReceiptsNotifier notifier) {
    if (notifier.error != null && notifier.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(notifier.error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => notifier.load(), child: const Text('Retry'))
          ],
        ),
      );
    }
    if (notifier.isEmpty && !notifier.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded, size: 80, color: AppColors.textMuted.withAlpha(80)),
            const SizedBox(height: 16),
            const Text('No receipts yet', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Drag and drop an image anywhere to begin', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    ReceiptData? selectedItem;
    if (_selectedReceiptId != null) {
      selectedItem = notifier.receipts.where((r) => r.receipt.id == _selectedReceiptId).firstOrNull;
    }

    return Row(
      children: [
        // LEFT PANE: Master List
        SizedBox(
          width: 320,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
              color: AppColors.surface,
            ),
            child: ListView.separated(
              itemCount: notifier.receipts.length,
              separatorBuilder: (cx, i) => const Divider(height: 1, indent: 64),
              itemBuilder: (context, index) {
                final item = notifier.receipts[index];
                final isSelected = item.receipt.id == _selectedReceiptId;
                
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: AppColors.primary.withAlpha(20),
                  leading: Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.surfaceElevated,
                    ),
                    child: Image.file(
                      File(item.image.filePath),
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(
                    item.receipt.total != null 
                        ? '\$${(item.receipt.total! / 100).toStringAsFixed(2)}' 
                        : 'Unknown Total',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
                  ),
                  subtitle: Text(
                    item.receipt.dateTime_?.toString().split(' ')[0] ?? 'Unknown Date',
                  ),
                  trailing: _buildBadge(item.receipt.status),
                  onTap: () {
                    if (_selectedReceiptId != item.receipt.id) {
                      setState(() {
                        _selectedReceiptId = item.receipt.id;
                        _isAdjustingCrop = false;
                        _ocrBoxes = null;
                        _ocrSize = null;
                      });
                    }
                  },
                );
              },
            ),
          ),
        ),

        // MIDDLE PANE: Viewer
        Expanded(
          child: Container(
            color: AppColors.background,
            child: selectedItem == null 
                ? const Center(child: Text('Select a receipt to view details', style: TextStyle(color: AppColors.textMuted)))
                : _buildViewerPane(selectedItem),
          ),
        ),

        // RIGHT PANE: Details
        if (selectedItem != null)
          ReceiptDetailsPanel(
            item: selectedItem,
            notifier: notifier,
            onOcrComplete: _onOcrComplete,
          ),
      ],
    );
  }

  Widget _buildViewerPane(ReceiptData item) {
    if (item.receipt.status == 'raw' || _isAdjustingCrop) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ReceiptCropperWidget(
            item: item,
            notifier: widget.notifier,
            onAccepted: _isAdjustingCrop
                ? () => setState(() => _isAdjustingCrop = false)
                : null,
          ),
          if (_isAdjustingCrop)
            Positioned(
              left: 16,
              top: 16,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isAdjustingCrop = false),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  backgroundColor: AppColors.surface,
                ),
              ),
            ),
        ],
      );
    } 
    
    // Otherwise show InteractiveViewer with standard Image (masked if cropPoints available)
    final points = item.receipt.cropPoints;
    
    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          boundaryMargin: EdgeInsets.zero,
          minScale: 0.8,
          maxScale: 5.0,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: points == null
                  ? _buildPlainImageWithBoxes(item)
                  : _buildWarpedImage(item, points),
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: FloatingActionButton.extended(
            onPressed: () => setState(() => _isAdjustingCrop = true),
            icon: const Icon(Icons.crop_rounded),
            label: const Text('Adjust Crop'),
            backgroundColor: AppColors.surfaceElevated,
            foregroundColor: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildPlainImageWithBoxes(ReceiptData item) {
    final boxes = _ocrBoxes;
    final ocrSize = _ocrSize;
    if (boxes == null || ocrSize == null || ocrSize.width <= 0 || ocrSize.height <= 0) {
      return Image.file(File(item.image.filePath), fit: BoxFit.contain);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;
        final scale = math.min(cw / ocrSize.width, ch / ocrSize.height);
        final dw = ocrSize.width * scale;
        final dh = ocrSize.height * scale;
        final ox = (cw - dw) / 2;
        final oy = (ch - dh) / 2;
        return SizedBox(
          width: cw,
          height: ch,
          child: Stack(
            children: [
              Image.file(File(item.image.filePath), width: cw, height: ch, fit: BoxFit.contain),
              ...boxes.map((box) => Positioned(
                left: ox + box.x1 * scale,
                top: oy + box.y1 * scale,
                width: (box.x2 - box.x1) * scale,
                height: (box.y2 - box.y1) * scale,
                child: _buildWordBox(box),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWarpedImage(ReceiptData item, CropPoints points) {
    return AspectRatio(
      aspectRatio: item.image.width > 0 && item.image.height > 0
          ? item.image.width / item.image.height
          : 0.7,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          
          final srcTl = Offset(points.topLeft.x * size.width, points.topLeft.y * size.height);
          final srcTr = Offset(points.topRight.x * size.width, points.topRight.y * size.height);
          final srcBr = Offset(points.bottomRight.x * size.width, points.bottomRight.y * size.height);
          final srcBl = Offset(points.bottomLeft.x * size.width, points.bottomLeft.y * size.height);

          final destWidth = math.max((srcTr - srcTl).distance, (srcBr - srcBl).distance);
          final destHeight = math.max((srcBl - srcTl).distance, (srcBr - srcTr).distance);

          if (destWidth <= 0 || destHeight <= 0) return const SizedBox();

          final matrix = PerspectiveMath.getPerspectiveTransform(
            srcTl: srcTl, srcTr: srcTr, srcBr: srcBr, srcBl: srcBl,
            destWidth: destWidth, destHeight: destHeight,
          );

          final boxes = _ocrBoxes;
          final ocrSize = _ocrSize;
          final scaleX = (ocrSize != null && ocrSize.width > 0) ? destWidth / ocrSize.width : 1.0;
          final scaleY = (ocrSize != null && ocrSize.height > 0) ? destHeight / ocrSize.height : 1.0;

          return Center(
            child: SizedBox(
              width: destWidth,
              height: destHeight,
              child: Stack(
                children: [
                  ClipRect(
                    child: Transform(
                      transform: matrix,
                      alignment: Alignment.topLeft,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        maxWidth: size.width,
                        maxHeight: size.height,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: Image.file(
                            File(item.image.filePath),
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (boxes != null)
                    ...boxes.map((box) => Positioned(
                      left: box.x1 * scaleX,
                      top: box.y1 * scaleY,
                      width: (box.x2 - box.x1) * scaleX,
                      height: (box.y2 - box.y1) * scaleY,
                      child: _buildWordBox(box),
                    )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadge(String status) {
    Color c;
    switch (status) {
      case 'raw': c = Colors.orange.shade700; break;
      case 'cropped': c = Colors.blue.shade600; break;
      case 'extracted': c = Colors.purple.shade500; break;
      case 'verified': c = AppColors.primary; break;
      default: c = AppColors.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c),
      ),
    );
  }
}

class _CropPointsClipper extends CustomClipper<Path> {
  final CropPoints points;
  _CropPointsClipper(this.points);

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(points.topLeft.x * size.width, points.topLeft.y * size.height)
      ..lineTo(points.topRight.x * size.width, points.topRight.y * size.height)
      ..lineTo(points.bottomRight.x * size.width, points.bottomRight.y * size.height)
      ..lineTo(points.bottomLeft.x * size.width, points.bottomLeft.y * size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _CropPointsClipper old) => false;
}
