import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:heic_to_png_jpg/heic_to_png_jpg.dart';
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
          try {
            final convertedPath = await HeicConverter.convertFile(
              inputPath: file.path,
              format: ImageFormat.jpg,
            );
            if (convertedPath != null && convertedPath.isNotEmpty) {
              await _repo.ingestRawReceipt(convertedPath);
            }
          } catch (e) {
            _error = 'Failed to load HEIC image. Your Windows computer is missing the required HEVC codec.';
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
}
