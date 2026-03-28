import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/core/database/tables.dart';
import 'package:bean_budget/core/repositories/receipt_repository.dart';

class ReceiptData {
  final Receipt receipt;
  final Image image;
  final Store? store;
  final List<ReceiptItem> items;

  ReceiptData(this.receipt, this.image, this.store, this.items);
}

class ReceiptsNotifier extends ChangeNotifier {
  final ReceiptRepository _repo;

  List<ReceiptData> _receipts = [];
  bool _isLoading = false;
  String? _error;

  ReceiptsNotifier(this._repo);

  List<ReceiptData> get receipts => _receipts;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isEmpty => _receipts.isEmpty;

  /// Loads all receipts and their attached physical images.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final allReceipts = await _repo.getAllReceipts();
      
      final results = <ReceiptData>[];
      for (final r in allReceipts) {
        if (r.imageId != null) {
          final img = await _repo.getImageForReceipt(r.id);
          if (img != null) {
            final items = await _repo.getItemsForReceipt(r.id);
            Store? store;
            if (r.storeId != null) {
              store = await _repo.getStoreById(r.storeId!);
            }
            results.add(ReceiptData(r, img, store, items));
          }
        }
      }
      _receipts = results;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Processes multiple dropped or selected files directly into the raw status.
  Future<void> importFiles(List<XFile> files) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      for (final file in files) {
        final ext = file.path.toLowerCase();
        
        if (ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png')) {
          await _repo.ingestRawReceipt(file.path);
        } else if (ext.endsWith('.heic') || ext.endsWith('.heif')) {
          final convertedPath = await _convertHeicViaWsl(file.path);
          if (convertedPath != null) {
            await _repo.ingestRawReceipt(convertedPath);
          } else {
            _error = 'Failed to convert HEIC image via WSL (pillow-heif).';
            _isLoading = false;
            notifyListeners();
            return;
          }
        }
      }
    } catch (e) {
      _error = e.toString();
    }
    
    _isLoading = false;
    await load();
  }

  Future<void> saveCropPoints(String receiptId, CropPoints points) async {
    await _repo.saveCropPoints(receiptId, points);
    await load();
  }

  Future<void> verifyReceipt({
    required String receiptId,
    String? storeId,
    String? categoryId,
    DateTime? dateTime,
    int? subtotal,
    int? total,
    int? amountCad,
  }) async {
    await _repo.updateReceiptMetadata(
      receiptId: receiptId,
      storeId: storeId,
      categoryId: categoryId,
      dateTime: dateTime,
      subtotal: subtotal,
      total: total,
      amountCad: amountCad,
      status: 'verified',
    );
    await load();
  }

  Future<void> deleteReceipt(String receiptId) async {
    await _repo.deleteReceipt(receiptId);
    await load();
  }

  Future<Store> findOrCreateStore(String name) async {
    return await _repo.findOrCreateStore(name);
  }

  Future<List<Store>> searchStores(String query) async {
    if (query.isEmpty) return [];
    return await _repo.searchStores(query);
  }

  Future<void> addReceiptItem(String receiptId, String name, int price, {String? categoryId}) async {
    await _repo.addReceiptItem(receiptId, name, price, categoryId: categoryId);
    await load();
  }

  Future<void> updateReceiptItem(String itemId, {String? name, int? price, String? categoryId}) async {
    await _repo.updateReceiptItem(itemId, name: name, price: price, categoryId: categoryId);
    // Note: Do not await load() aggressively on every keystroke save, it might rebuild text fields. 
    // Wait, since we are calling it onChange, doing `await load()` re-fetches and replaces the text fields, losing cursor focus! 
    // We should just update the DB silently.
  }

  Future<void> deleteReceiptItem(String itemId) async {
    await _repo.deleteReceiptItem(itemId);
    await load();
  }

  /// Runs Canny-contour detection in WSL Python to auto-detect the receipt
  /// bounding box.  Returns null if detection fails or produces no candidate.
  Future<CropPoints?> detectReceiptBbox(String imagePath) async {
    const script = r"""
import sys, json, cv2, numpy as np
from PIL import Image
path = sys.argv[1]
pil = Image.open(path).convert('RGB')
s = 800 / max(pil.size)
if s < 1.0: pil = pil.resize((int(pil.width*s), int(pil.height*s)), Image.LANCZOS)
img = np.array(pil)
h, w = img.shape[:2]
gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
blurred = cv2.GaussianBlur(gray, (5,5), 0)
med = float(np.median(blurred))
edges = cv2.Canny(blurred, max(0,int(0.66*med)), min(255,int(1.33*med)))
k = cv2.getStructuringElement(cv2.MORPH_RECT, (5,5))
edges = cv2.dilate(edges, k, iterations=2)
contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
min_area = 0.05 * w * h
cands = []
for c in contours:
    cx,cy,cw,ch = cv2.boundingRect(c)
    area = cw*ch
    if area < min_area: continue
    hull = cv2.convexHull(c)
    sol = cv2.contourArea(hull)/area if area > 0 else 0
    cands.append((area,sol,cx,cy,cw,ch))
if not cands: print('null')
else:
    solid = [c for c in cands if c[1] > 0.5]
    _,_,cx,cy,cw,ch = max(solid or cands, key=lambda c: c[0])
    print(json.dumps({'x0': cx/w, 'y0': cy/h, 'x1': (cx+cw)/w, 'y1': (cy+ch)/h}))
""";
    final wslPath = _toWslPath(imagePath);
    final result = await Process.run('wsl', ['python3.8', '-c', script, wslPath]);
    if (result.exitCode != 0) return null;
    final output = (result.stdout as String).trim();
    if (output == 'null' || output.isEmpty) return null;
    try {
      final m = json.decode(output) as Map<String, dynamic>;
      final x0 = (m['x0'] as num).toDouble();
      final y0 = (m['y0'] as num).toDouble();
      final x1 = (m['x1'] as num).toDouble();
      final y1 = (m['y1'] as num).toDouble();
      return CropPoints(
        topLeft:     Coordinate(x: x0, y: y0),
        topRight:    Coordinate(x: x1, y: y0),
        bottomRight: Coordinate(x: x1, y: y1),
        bottomLeft:  Coordinate(x: x0, y: y1),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _convertHeicViaWsl(String inputPath) async {
    final wslInput = _toWslPath(inputPath);
    final baseName = inputPath.split(r'\').last;
    final outName = baseName.replaceAll(RegExp(r'\.(heic|heif)$', caseSensitive: false), '.jpg');
    final tempDir = Directory.systemTemp.path;
    final wslOutput = '${_toWslPath(tempDir)}/$outName';
    final windowsOutput = '$tempDir\\$outName';

    final result = await Process.run('wsl', [
      'python3.10', '-c',
      'from PIL import Image; from pillow_heif import register_heif_opener; '
      'register_heif_opener(); '
      'Image.open("$wslInput").convert("RGB").save("$wslOutput", "JPEG", quality=95)',
    ]);

    if (result.exitCode != 0) return null;
    return windowsOutput;
  }

  String _toWslPath(String windowsPath) {
    final normalized = windowsPath.replaceAll('\\', '/');
    if (normalized.length >= 2 && normalized[1] == ':') {
      final drive = normalized[0].toLowerCase();
      final rest = normalized.substring(2);
      return '/mnt/$drive$rest';
    }
    return normalized;
  }
}
