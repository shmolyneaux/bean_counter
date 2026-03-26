import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/core/database/tables.dart';

class ReceiptRepository {
  final AppDatabase _db;
  static const _uuid = Uuid();

  ReceiptRepository(this._db);

  /// Generates a SHA-256 hash of a file for deduplication (optional future use) or naming.
  Future<String> _hashFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Copies a raw image file into the app's secure internal storage directory.
  Future<File> _copyToInternalStorage(File source) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'BeanBudget', 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    
    // Hash the file to create a unique, collision-free filename that also acts as a deduplication check
    final hash = await _hashFile(source);
    final ext = p.extension(source.path).toLowerCase();
    final newPath = p.join(imagesDir.path, '$hash$ext');
    
    final newFile = File(newPath);
    if (!await newFile.exists()) {
      await source.copy(newPath);
    }
    return newFile;
  }

  /// Gets image dimensions. Will throw if the image is invalid.
  Future<ui.Image> _getImageInfo(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Ingests a new receipt image into the raw pipeline stage.
  Future<Receipt> ingestRawReceipt(String sourceFilePath) async {
    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('File not found: $sourceFilePath');
    }

    // 1. Copy image to internal app storage
    final internalFile = await _copyToInternalStorage(sourceFile);
    
    // 2. Decode dimensions
    final imageInfo = await _getImageInfo(internalFile);

    // 3. Insert Image record
    final imageId = _uuid.v4();
    await _db.into(_db.images).insert(
      ImagesCompanion.insert(
        id: imageId,
        filePath: internalFile.path,
        originalFilename: p.basename(sourceFilePath),
        mimeType: const Value('image/jpeg'), // simplistic default
        width: Value(imageInfo.width),
        height: Value(imageInfo.height),
      ),
    );
    
    // 4. Insert Receipt record in 'raw' status
    final receiptId = _uuid.v4();
    await _db.into(_db.receipts).insert(
      ReceiptsCompanion.insert(
        id: receiptId,
        imageId: Value(imageId),
        status: const Value('raw'),
      ),
    );

    return (await getReceiptById(receiptId))!;
  }

  /// Saves the cropping coordinates (e.g. from the Cropper UI) and advances status to 'cropped'.
  Future<Receipt> saveCropPoints(String receiptId, CropPoints points) async {
    await (_db.update(_db.receipts)..where((r) => r.id.equals(receiptId))).write(
      ReceiptsCompanion(
        cropPoints: Value(points),
        status: const Value('cropped'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await getReceiptById(receiptId))!;
  }

  /// Fully annotates a receipt and advances status to 'verified'.
  Future<Receipt> updateReceiptMetadata({
    required String receiptId,
    String? storeId,
    String? categoryId,
    DateTime? dateTime,
    int? subtotal,
    int? total,
    int? amountCad,
    String? lastFourCc,
    String status = 'verified',
  }) async {
    await (_db.update(_db.receipts)..where((r) => r.id.equals(receiptId))).write(
      ReceiptsCompanion(
        storeId: Value(storeId),
        categoryId: Value(categoryId),
        dateTime_: Value(dateTime),
        subtotal: Value(subtotal),
        total: Value(total),
        amountCad: Value(amountCad),
        lastFourCc: Value(lastFourCc),
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await getReceiptById(receiptId))!;
  }

  /// Get a single receipt by ID.
  Future<Receipt?> getReceiptById(String id) {
    return (_db.select(_db.receipts)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Get the backing Image record for a receipt
  Future<Image?> getImageForReceipt(String receiptId) async {
    final receipt = await getReceiptById(receiptId);
    if (receipt == null || receipt.imageId == null) return null;
    return (_db.select(_db.images)..where((i) => i.id.equals(receipt.imageId!))).getSingleOrNull();
  }

  /// Get all receipts.
  Future<List<Receipt>> getAllReceipts() {
    return (_db.select(_db.receipts)..orderBy([(r) => OrderingTerm.desc(r.createdAt)])).get();
  }

  /// Searches for stores by name (case insensitive).
  Future<List<Store>> searchStores(String query) async {
    return (_db.select(_db.stores)
          ..where((s) => s.name.like('%$query%'))
          ..orderBy([(s) => OrderingTerm.asc(s.name)])
          ..limit(10))
        .get();
  }

  /// Finds a store by exact name or creates it.
  Future<Store> findOrCreateStore(String name) async {
    final existing = await (_db.select(_db.stores)..where((s) => s.name.equalsExp(Variable.withString(name)))).getSingleOrNull();
    if (existing != null) return existing;

    final id = _uuid.v4();
    final newStore = StoresCompanion.insert(id: id, name: name);
    await _db.into(_db.stores).insert(newStore);
    return (await (_db.select(_db.stores)..where((s) => s.id.equals(id))).getSingle())!;
  }

  /// Gets a store by ID.
  Future<Store?> getStoreById(String storeId) {
    return (_db.select(_db.stores)..where((s) => s.id.equals(storeId))).getSingleOrNull();
  }

  /// Gets all receipt items for a receipt, sorted by sortOrder.
  Future<List<ReceiptItem>> getItemsForReceipt(String receiptId) async {
    return (_db.select(_db.receiptItems)
          ..where((i) => i.receiptId.equals(receiptId))
          ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
        .get();
  }

  /// Adds a new receipt item.
  Future<ReceiptItem> addReceiptItem(String receiptId, String name, int price, {bool isTaxable = false, String? categoryId, int sortOrder = 0}) async {
    final id = _uuid.v4();
    await _db.into(_db.receiptItems).insert(ReceiptItemsCompanion.insert(
      id: id,
      receiptId: receiptId,
      itemName: name,
      price: price,
      isTaxable: Value(isTaxable),
      categoryId: Value(categoryId),
      sortOrder: Value(sortOrder),
    ));
    return (await (_db.select(_db.receiptItems)..where((i) => i.id.equals(id))).getSingle())!;
  }

  /// Updates an existing receipt item.
  Future<void> updateReceiptItem(String itemId, {String? name, int? price, bool? isTaxable, String? categoryId, int? sortOrder}) async {
    await (_db.update(_db.receiptItems)..where((i) => i.id.equals(itemId))).write(ReceiptItemsCompanion(
      itemName: name != null ? Value(name) : const Value.absent(),
      price: price != null ? Value(price) : const Value.absent(),
      isTaxable: isTaxable != null ? Value(isTaxable) : const Value.absent(),
      categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
      sortOrder: sortOrder != null ? Value(sortOrder) : const Value.absent(),
    ));
  }

  /// Deletes a receipt item.
  Future<void> deleteReceiptItem(String itemId) async {
    await (_db.delete(_db.receiptItems)..where((i) => i.id.equals(itemId))).go();
  }

  /// Hard-deletes a receipt, its items, and its physical image file.
  Future<void> deleteReceipt(String receiptId) async {
    final receipt = await getReceiptById(receiptId);
    if (receipt == null) return;

    // Delete items
    await (_db.delete(_db.receiptItems)..where((i) => i.receiptId.equals(receiptId))).go();

    // Delete receipt
    await (_db.delete(_db.receipts)..where((r) => r.id.equals(receiptId))).go();

    // Try to delete image
    if (receipt.imageId != null) {
      final img = await (_db.select(_db.images)..where((i) => i.id.equals(receipt.imageId!))).getSingleOrNull();
      if (img != null) {
        // If no other receipts reference this image, physically delete it
        final links = await (_db.select(_db.receipts)..where((r) => r.imageId.equals(img.id))).get();
        if (links.isEmpty) {
          try {
            final file = File(img.filePath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
          await (_db.delete(_db.images)..where((i) => i.id.equals(img.id))).go();
        }
      }
    }
  }
}
