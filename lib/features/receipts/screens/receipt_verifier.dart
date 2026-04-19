import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:bean_budget/core/database/database.dart' hide Image;
import 'package:bean_budget/core/database/tables.dart' hide Image;
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/utils/perspective_math.dart';
import 'package:bean_budget/features/receipts/receipts_notifier.dart';
import 'package:bean_budget/features/categories/widgets/category_pickers.dart';

class OcrBox {
  final String word;
  final double confidence;
  final int x1, y1, x2, y2;
  final int blockNum, parNum, lineNum, wordNum;

  const OcrBox({
    required this.word,
    required this.confidence,
    required this.x1, required this.y1,
    required this.x2, required this.y2,
    required this.blockNum, required this.parNum,
    required this.lineNum, required this.wordNum,
  });
}


class ReceiptDetailsPanel extends StatefulWidget {
  final ReceiptData item;
  final ReceiptsNotifier notifier;
  final void Function(String receiptId, List<OcrBox>?, Size?) onOcrComplete;

  const ReceiptDetailsPanel({
    super.key,
    required this.item,
    required this.notifier,
    required this.onOcrComplete,
  });

  @override
  State<ReceiptDetailsPanel> createState() => _ReceiptDetailsPanelState();
}

class _ReceiptDetailsPanelState extends State<ReceiptDetailsPanel> {
  late DateTime? _date;
  late TextEditingController _totalController;
  late TextEditingController _subtotalController;
  late TextEditingController _storeController;
  late FocusNode _storeFocusNode;

  String? _selectedStoreId;
  String? _selectedStoreName;
  String? _selectedCategoryId;

  List<Category> _allCategories = [];
  bool _confirmingDelete = false;
  Timer? _debounce;
  
  bool _isOcrRunning = false;

  // In-memory cache keyed by "receiptId/imageId/cropHash".
  static final Map<String, (List<OcrBox>?, Size?)> _ocrCache = {};
  static Directory? _ocrCacheDir;

  String get _cacheKey {
    final crop = widget.item.receipt.cropPoints;
    final cropKey = crop == null ? 'none' : const CropPointsConverter().toSql(crop);
    return '${widget.item.receipt.id}/${widget.item.image.id}/$cropKey';
  }

  // Stable filename for disk cache — just the receipt ID.
  String get _cacheFileName => '${widget.item.receipt.id}.json';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _initValues();
  }

  @override
  void didUpdateWidget(covariant ReceiptDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.receipt.id != widget.item.receipt.id) {
      _initValues();
      _confirmingDelete = false;
    }
    if (oldWidget.item.image.id != widget.item.image.id ||
        oldWidget.item.receipt.cropPoints != widget.item.receipt.cropPoints) {
      _extractOcrText();
    }
  }

  Future<void> _extractOcrText() async {
    if (_isOcrRunning) return;

    // Capture identity before any await — widget may be updated while we run.
    final receiptId = widget.item.receipt.id;
    final key = _cacheKey;
    final fileName = _cacheFileName;

    // 1. In-memory cache.
    if (_ocrCache.containsKey(key)) {
      final (boxes, size) = _ocrCache[key]!;
      widget.onOcrComplete(receiptId, boxes, size);
      return;
    }

    // 2. Disk cache.
    final diskResult = await _loadFromDisk(fileName, key);
    if (diskResult != null) {
      _ocrCache[key] = diskResult;
      widget.onOcrComplete(receiptId, diskResult.$1, diskResult.$2);
      return;
    }

    setState(() => _isOcrRunning = true);

    try {
      final imageFile = File(widget.item.image.filePath);
      if (!await imageFile.exists()) {
        if (mounted) setState(() => _isOcrRunning = false);
        widget.onOcrComplete(receiptId, null, null);
        return;
      }

      final rawBytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      Uint8List tessBytes;
      Size tessSize;

      final cropPoints = widget.item.receipt.cropPoints;
      if (cropPoints != null) {
        (tessBytes, tessSize) = await _buildWarpedBytes(uiImage, cropPoints);
      } else {
        tessBytes = rawBytes;
        tessSize = Size(uiImage.width.toDouble(), uiImage.height.toDouble());
      }
      uiImage.dispose();

      // Write to a temp file and run WSL tesseract CLI.
      final tmpFile = File('${Directory.systemTemp.path}\\ocr_tmp_${DateTime.now().millisecondsSinceEpoch}.png');
      await tmpFile.writeAsBytes(tessBytes);
      try {
        final wslPath = _toWslPath(tmpFile.path);
        final result = await Process.run('wsl', [
          'tesseract', wslPath, 'stdout', '--oem', '1', '--psm', '4', 'tsv',
        ]);
        final boxes = result.exitCode == 0 ? _parseTsv(result.stdout as String) : <OcrBox>[];
        _ocrCache[key] = (boxes, tessSize);
        if (boxes.isNotEmpty) await _saveToDisk(fileName, key, boxes, tessSize);
        if (mounted) setState(() => _isOcrRunning = false);
        widget.onOcrComplete(receiptId, boxes, tessSize);
      } finally {
        await tmpFile.delete().catchError((_) {});
      }
    } catch (e) {
      if (mounted) setState(() => _isOcrRunning = false);
      widget.onOcrComplete(receiptId, null, null);
    }
  }

  static Future<Directory> _getOcrCacheDir() async {
    if (_ocrCacheDir != null) return _ocrCacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'BeanBudget', 'ocr_cache'));
    await dir.create(recursive: true);
    _ocrCacheDir = dir;
    return dir;
  }

  static Future<(List<OcrBox>, Size)?> _loadFromDisk(String fileName, String key) async {
    try {
      final dir = await _getOcrCacheDir();
      final file = File(p.join(dir.path, fileName));
      if (!await file.exists()) return null;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Invalidate if crop points changed since this was written.
      if (map['key'] != key) return null;
      final sizeMap = map['size'] as Map<String, dynamic>;
      final size = Size((sizeMap['w'] as num).toDouble(), (sizeMap['h'] as num).toDouble());
      final boxes = (map['boxes'] as List<dynamic>).map((b) {
        final m = b as Map<String, dynamic>;
        return OcrBox(
          word: m['w'] as String, confidence: (m['c'] as num).toDouble(),
          x1: m['x1'] as int, y1: m['y1'] as int,
          x2: m['x2'] as int, y2: m['y2'] as int,
          blockNum: m['bn'] as int, parNum: m['pn'] as int,
          lineNum: m['ln'] as int, wordNum: m['wn'] as int,
        );
      }).toList();
      return (boxes, size);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToDisk(String fileName, String key, List<OcrBox> boxes, Size size) async {
    try {
      final dir = await _getOcrCacheDir();
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString(jsonEncode({
        'key': key,
        'size': {'w': size.width, 'h': size.height},
        'boxes': boxes.map((b) => {
          'w': b.word, 'c': b.confidence,
          'x1': b.x1, 'y1': b.y1, 'x2': b.x2, 'y2': b.y2,
          'bn': b.blockNum, 'pn': b.parNum, 'ln': b.lineNum, 'wn': b.wordNum,
        }).toList(),
      }));
    } catch (_) {}
  }

  static List<OcrBox> _parseTsv(String tsv) {
    final boxes = <OcrBox>[];
    final lines = tsv.split('\n');
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cols = line.split('\t');
      if (cols.length < 12) continue;
      if ((int.tryParse(cols[0]) ?? 0) != 5) continue; // word level only
      final conf = double.tryParse(cols[10]) ?? -1;
      if (conf < 0) continue;
      final word = cols[11];
      if (word.trim().isEmpty) continue;
      final left   = int.tryParse(cols[6]) ?? 0;
      final top    = int.tryParse(cols[7]) ?? 0;
      final width  = int.tryParse(cols[8]) ?? 0;
      final height = int.tryParse(cols[9]) ?? 0;
      boxes.add(OcrBox(
        word: word, confidence: conf,
        x1: left, y1: top, x2: left + width, y2: top + height,
        blockNum: int.tryParse(cols[2]) ?? 0,
        parNum:   int.tryParse(cols[3]) ?? 0,
        lineNum:  int.tryParse(cols[4]) ?? 0,
        wordNum:  int.tryParse(cols[5]) ?? 0,
      ));
    }
    return boxes;
  }

  static String _toWslPath(String windowsPath) {
    final normalized = windowsPath.replaceAll('\\', '/');
    if (normalized.length >= 2 && normalized[1] == ':') {
      return '/mnt/${normalized[0].toLowerCase()}${normalized.substring(2)}';
    }
    return normalized;
  }

  Future<(Uint8List, Size)> _buildWarpedBytes(ui.Image uiImage, CropPoints points) async {
    final w = uiImage.width.toDouble();
    final h = uiImage.height.toDouble();

    final srcTl = Offset(points.topLeft.x * w, points.topLeft.y * h);
    final srcTr = Offset(points.topRight.x * w, points.topRight.y * h);
    final srcBr = Offset(points.bottomRight.x * w, points.bottomRight.y * h);
    final srcBl = Offset(points.bottomLeft.x * w, points.bottomLeft.y * h);

    final destWidth = math.max((srcTr - srcTl).distance, (srcBr - srcBl).distance);
    final destHeight = math.max((srcBl - srcTl).distance, (srcBr - srcTr).distance);

    final matrix = PerspectiveMath.getPerspectiveTransform(
      srcTl: srcTl, srcTr: srcTr, srcBr: srcBr, srcBl: srcBl,
      destWidth: destWidth, destHeight: destHeight,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.transform(matrix.storage);
    canvas.drawImage(uiImage, Offset.zero, Paint());

    final picture = recorder.endRecording();
    final output = await picture.toImage(destWidth.round(), destHeight.round());
    final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
    output.dispose();

    return (byteData!.buffer.asUint8List(), Size(destWidth, destHeight));
  }

  Future<void> _loadCategories() async {
    final db = AppDatabase.instance();
    final allCats = await (db.select(db.categories)..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.name)])).get();

    // Organize hierarchically parents then children
    final List<Category> sortedCats = [];
    final parents = allCats.where((c) => c.parentId == null).toList();
    for (final p in parents) {
      sortedCats.add(p);
      final children = allCats.where((c) => c.parentId == p.id).toList();
      sortedCats.addAll(children);
    }
    for (final c in allCats) {
      if (!sortedCats.contains(c)) sortedCats.add(c);
    }

    if (mounted) {
      setState(() => _allCategories = sortedCats);
    }
  }

  void _initValues() {
    _date = widget.item.receipt.dateTime_;
    _totalController = TextEditingController(
      text: widget.item.receipt.total != null 
          ? (widget.item.receipt.total! / 100).toStringAsFixed(2) 
          : '',
    );
    _subtotalController = TextEditingController(
      text: widget.item.receipt.subtotal != null 
          ? (widget.item.receipt.subtotal! / 100).toStringAsFixed(2) 
          : '',
    );
    _storeController = TextEditingController(text: widget.item.store?.name ?? '');
    _storeFocusNode = FocusNode();
    _selectedStoreId = widget.item.receipt.storeId;
    _selectedStoreName = widget.item.store?.name;
    _selectedCategoryId = widget.item.receipt.categoryId;
    
    _isOcrRunning = false;
    _extractOcrText();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _totalController.dispose();
    _subtotalController.dispose();
    _storeController.dispose();
    _storeFocusNode.dispose();
    super.dispose();
  }

  int? _parsePennies(String value) {
    if (value.isEmpty) return null;
    final cleaned = value.trim().replaceFirst(RegExp(r'^\$'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed == null) return null;
    return (parsed * 100).round();
  }

  void _debouncedSave() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _save());
  }

  Future<void> _save() async {
    String? finalStoreId = _selectedStoreId;
    final typedStore = _storeController.text.trim();
    if (typedStore.isNotEmpty) {
      if (_selectedStoreName != typedStore) {
        final newStore = await widget.notifier.findOrCreateStore(typedStore);
        finalStoreId = newStore.id;
        _selectedStoreName = newStore.name;
        _selectedStoreId = newStore.id;
      }
    } else {
      finalStoreId = null;
      _selectedStoreName = null;
      _selectedStoreId = null;
    }

    await widget.notifier.verifyReceipt(
      receiptId: widget.item.receipt.id,
      storeId: finalStoreId,
      categoryId: _selectedCategoryId,
      dateTime: _date,
      total: _parsePennies(_totalController.text),
      subtotal: _parsePennies(_subtotalController.text),
    );
  }

  Future<void> _deleteReceipt() async {
    if (_confirmingDelete) {
      await widget.notifier.deleteReceipt(widget.item.receipt.id);
    } else {
      setState(() => _confirmingDelete = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildMetadataForm(),
                const SizedBox(height: 32),
                _buildLineItemsSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Receipt Details',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _deleteReceipt,
                tooltip: _confirmingDelete ? 'Confirm Delete' : 'Delete Receipt',
                icon: Icon(_confirmingDelete ? Icons.delete_forever_rounded : Icons.delete_outline_rounded),
                color: _confirmingDelete ? AppColors.error : AppColors.textSecondary,
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMetadataForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Store Field
        const Text('Store / Merchant', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        RawAutocomplete<Store>(
          textEditingController: _storeController,
          focusNode: _storeFocusNode,
          displayStringForOption: (s) => s.name,
          optionsBuilder: (textEditingValue) async {
            if (textEditingValue.text.isEmpty) return const Iterable<Store>.empty();
            return await widget.notifier.searchStores(textEditingValue.text);
          },
          onSelected: (Store selection) {
            _selectedStoreId = selection.id;
            _selectedStoreName = selection.name;
            _storeController.text = selection.name;
            _save();
          },
          fieldViewBuilder: (context, controller, focus, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focus,
              onChanged: (v) => _debouncedSave(),
              decoration: const InputDecoration(
                hintText: 'Search or enter new store',
                prefixIcon: Icon(Icons.storefront_rounded, color: AppColors.textMuted),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 370,
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        title: Text(option.name),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // Date Field
        const Text('Date', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() => _date = picked);
              _save();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _date == null ? 'Select Date' : DateFormat('MMM dd, yyyy').format(_date!),
                ),
                const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Global Category (Always visible, changes label if there are line items)
        Text(
          widget.item.items.isEmpty ? 'Global Category' : 'Default Category',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        _InstantCategoryDropdown(
          value: _selectedCategoryId,
          allCategories: _allCategories,
          onChanged: (val) {
            setState(() => _selectedCategoryId = val);
            _save();
          },
        ),
        const SizedBox(height: 16),

        // Subtotal & Total row
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subtotal', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _subtotalController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '\$ 0.00'),
                    onChanged: (v) => _debouncedSave(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _totalController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '\$ 0.00'),
                    onChanged: (v) => _debouncedSave(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLineItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Line Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (widget.item.items.isEmpty)
          const Text('No individual items tracked for this receipt.', style: TextStyle(color: AppColors.textMuted))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.item.items.length,
            separatorBuilder: (c, i) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return _ExistingLineItemRow(
                item: widget.item.items[index],
                notifier: widget.notifier,
                allCategories: _allCategories,
              );
            },
          ),
        
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: () => _addNewItemRow(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Item'),
          ),
        ),
      ],
    );
  }

  void _addNewItemRow() {
    widget.notifier.addReceiptItem(
      widget.item.receipt.id,
      'TODO',
      0,
      categoryId: _selectedCategoryId,
    );
  }

}

class _InstantCategoryDropdown extends StatefulWidget {
  final String? value;
  final List<Category> allCategories;
  final ValueChanged<String?> onChanged;

  const _InstantCategoryDropdown({
    super.key,
    required this.value,
    required this.allCategories,
    required this.onChanged,
  });

  @override
  State<_InstantCategoryDropdown> createState() => _InstantCategoryDropdownState();
}

class _InstantCategoryDropdownState extends State<_InstantCategoryDropdown> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeDropdown,
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, size.height + 4),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: widget.allCategories.map((c) {
                        final isSub = c.parentId != null;
                        return InkWell(
                          onTap: () {
                            widget.onChanged(c.id);
                            _closeDropdown();
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12).copyWith(left: isSub ? 40 : 16),
                            child: Row(
                              children: [
                                Icon(IconPickerGrid.resolveIcon(c.icon), color: Color(c.color), size: 18),
                                const SizedBox(width: 8),
                                Text(isSub ? '↳ ${c.name}' : c.name),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  @override
  void dispose() {
    _closeDropdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategory = widget.allCategories.where((c) => c.id == widget.value).firstOrNull;

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _isOpen ? AppColors.primary : AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (selectedCategory != null)
                Row(
                  children: [
                    Icon(IconPickerGrid.resolveIcon(selectedCategory.icon), color: Color(selectedCategory.color), size: 18),
                    const SizedBox(width: 8),
                    Text(selectedCategory.name),
                  ],
                )
              else
                const Text('Select a category', style: TextStyle(color: AppColors.textMuted)),
              Icon(_isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingLineItemRow extends StatefulWidget {
  final ReceiptItem item;
  final ReceiptsNotifier notifier;
  final List<Category> allCategories;

  const _ExistingLineItemRow({required this.item, required this.notifier, required this.allCategories});

  @override
  State<_ExistingLineItemRow> createState() => _ExistingLineItemRowState();
}

class _ExistingLineItemRowState extends State<_ExistingLineItemRow> {
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  String? _catId;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.itemName == 'TODO' ? '' : widget.item.itemName);
    _priceCtrl = TextEditingController(text: (widget.item.price / 100).toStringAsFixed(2));
    _catId = widget.item.categoryId;
  }

  void _saveItem() {
    final parsed = double.tryParse(_priceCtrl.text) ?? 0.0;
    widget.notifier.updateReceiptItem(
      widget.item.id,
      name: _nameCtrl.text.isEmpty ? 'TODO' : _nameCtrl.text,
      price: (parsed * 100).round(),
      categoryId: _catId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(hintText: 'Item name', isDense: true, border: InputBorder.none),
                  onChanged: (v) => _saveItem(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Price', isDense: true, border: InputBorder.none),
                  onChanged: (v) => _saveItem(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error, size: 20),
                onPressed: () => widget.notifier.deleteReceiptItem(widget.item.id),
              )
            ],
          ),
          const SizedBox(height: 8),
          _InstantCategoryDropdown(
            value: _catId,
            allCategories: widget.allCategories,
            onChanged: (v) {
              setState(() => _catId = v);
              _saveItem();
            },
          )
        ],
      ),
    );
  }
}
