# BeanBudget — Flutter Expense Tracking App

A Windows-native Flutter app for tracking personal expenses by importing bank/credit card statements and receipts, categorizing line items, and generating monthly spending reports.

**Platform:** Windows only
**Currency:** CAD (default), with optional foreign-currency support on receipts
**Philosophy:** Minimal dependencies, simple state management

---

## Data Model

### Store
```
Store
├── id (UUID)
├── name (String)
├── default_category_id (FK → Category, nullable)
├── created_at
└── updated_at
```

### Receipt
All fields nullable except `id`, `status`, `created_at`, `updated_at` — since a receipt starts as just an uploaded image and gets annotated progressively.

```
Receipt
├── id (UUID)
├── uncropped_image_id (FK → Image, nullable)
├── cropped_image_id (FK → Image, nullable)
├── datetime (nullable)
├── last_four_cc (String, 4 chars, nullable)
├── subtotal (int, cents, nullable)
├── total (int, cents, nullable)
├── amount_cad (int, cents, nullable — set only for foreign-currency purchases)
├── store_id (FK → Store, nullable)
├── statement_line_id (FK → StatementLine, nullable)
├── status (enum: raw | cropped | extracted | verified)
├── created_at
├── updated_at
└── items: List<ReceiptItem>
```

**Tax** is always derived as `total - subtotal`. No explicit tax field.

**`amount_cad`**: For domestic purchases this is `null`. For foreign purchases, the UI shows a "Foreign currency?" checkbox that reveals an input for the CAD equivalent.

### ReceiptItem
```
ReceiptItem
├── id (UUID)
├── receipt_id (FK → Receipt)
├── item_name (String)
├── price (int, cents)
├── is_taxable (bool)
├── category_id (FK → Category, nullable)
└── sort_order (int — preserve receipt ordering)
```

Tax is tracked per item so that tax paid can be attributed to individual taxable items. Without this, non-taxable groceries on a mixed receipt would appear to cost more than they actually do. The tax amount is distributed proportionally across taxable items for reporting.

### Statement
```
Statement
├── id (UUID)
├── source (String — e.g., "TD Visa", "RBC Chequing")
├── account_last_four (String)
├── statement_period_start (Date)
├── statement_period_end (Date)
├── file_path (String — original PDF/CSV)
├── created_at
└── lines: List<StatementLine>
```

### StatementLine
```
StatementLine
├── id (UUID)
├── statement_id (FK → Statement)
├── date (Date)
├── payee (String)
├── amount (int, cents — always positive, expenses only)
├── category_id (FK → Category, nullable)
├── receipt_id (FK → Receipt, nullable — links to receipt for breakdown)
├── notes (String, nullable)
└── sort_order (int)
```

### Category
```
Category
├── id (UUID)
├── name (String)
├── parent_id (FK → Category, nullable — for sub-categories)
├── icon (String — material icon name)
├── color (int — hex color value)
└── sort_order (int)
```

### PayeeRule
Auto-assigns a category to statement lines based on payee name pattern.

```
PayeeRule
├── id (UUID)
├── pattern (String — e.g., "NETFLIX", "MORTGAGE")
├── match_type (enum: exact | contains | starts_with)
├── category_id (FK → Category)
├── store_id (FK → Store, nullable — also auto-assign store if applicable)
├── created_at
└── updated_at
```

When a statement is imported, each line's payee is checked against PayeeRules. If matched, the category (and optionally store) is auto-assigned.

### Image
```
Image
├── id (UUID)
├── file_path (String — relative to app storage)
├── original_filename (String)
├── mime_type (String)
├── width (int)
├── height (int)
└── created_at
```

### CsvProfile
Stores column mapping for a bank's CSV format so it doesn't need to be re-mapped on each import.

```
CsvProfile
├── id (UUID)
├── name (String — e.g., "TD Visa CSV")
├── date_column (int)
├── payee_column (int)
├── amount_column (int)
├── delimiter (String, default ",")
├── has_header_row (bool)
├── date_format (String — e.g., "MM/dd/yyyy")
├── created_at
└── updated_at
```

---

## Architecture

### Project Structure (Feature-First + Repository Pattern)

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── database/          # drift DB setup, tables, DAOs, migrations
│   ├── models/            # Plain Dart classes for domain models
│   ├── repositories/      # Data access layer (wraps drift DAOs)
│   ├── services/          # Business logic (CSV parsing, payee matching)
│   ├── theme/             # App theme, colors, typography
│   └── utils/             # Currency formatters, date helpers
├── features/
│   ├── receipts/
│   │   ├── screens/       # Receipt list, detail, crop, annotate
│   │   └── widgets/       # Receipt card, item editor, image viewer
│   ├── statements/
│   │   ├── screens/       # Statement list, detail, CSV import
│   │   └── widgets/       # Statement line row, column mapper
│   ├── categories/
│   │   ├── screens/       # Category list, edit, payee rules
│   │   └── widgets/       # Category picker, color/icon picker
│   └── reports/
│       ├── screens/       # Monthly spending breakdown
│       └── widgets/       # Summary cards, category breakdown list
└── shared/
    └── widgets/           # Shared components (dialogs, form fields)
```

### State Management

**`ChangeNotifier` + `ListenableBuilder`** — Flutter's built-in approach. No external state management package.

Each feature gets a simple notifier class:
```dart
class ReceiptListNotifier extends ChangeNotifier {
  final ReceiptRepository _repo;
  List<Receipt> _receipts = [];
  // ... load, add, update, notify
}
```

Notifiers are created at the app level and passed down via constructor injection or `InheritedWidget`.

### Database: drift

- Type-safe SQLite queries generated from Dart table definitions
- Clean migration system for schema evolution
- Supports complex joins (receipt ↔ statement ↔ category)
- Works natively on Windows via `sqlite3_flutter_libs`

---

## File Storage

```
App Documents Directory/
├── images/
│   ├── originals/         # Uncropped receipt photos
│   └── cropped/           # Cropped receipt images
├── statements/            # Original PDF/CSV files
└── database/
    └── bean_budget.db
```

---

## Statement Parsing

### CSV Parsing
- Use the **`csv`** Dart package
- Different banks use different column layouts — build a **column mapper UI** on first import
- Save the mapping as a **CsvProfile** per bank source, so subsequent imports auto-map

### PDF Parsing (Phase 2)
- Use **`pdfx`** for text extraction from PDF statements
- Bank-specific parsing will be needed — start with one bank's format and expand
- PDF support comes after CSV is solid

---

## Receipt Processing Pipeline

```
raw → cropped → extracted → verified
```

| Status | Description |
|---|---|
| `raw` | Image uploaded, nothing else done |
| `cropped` | Receipt area cropped from image |
| `extracted` | Items, total, store, date entered (manually for now) |
| `verified` | User has reviewed and confirmed all data is correct |

The Receipts tab should prominently surface receipts that need attention (not yet `verified`).

### Image Input
- **File picker dialog** for selecting images from disk
- **Drag-and-drop** onto the app window for quick receipt upload

### Image Cropping
- **Custom-built cropper** using Flutter's `CustomPainter` + drag handles
- No external cropping library (limited Windows support)

---

## Default Categories (Seed Data)

| Category | Sub-categories |
|---|---|
| Housing | Mortgage, Rent, Property Tax, HOA, Maintenance |
| Insurance | Health, Auto, Home, Life |
| Utilities | Electric, Gas, Water, Internet, Phone |
| Groceries | Food, Household, Personal Care |
| Transportation | Gas, Maintenance, Parking, Tolls, Transit |
| Dining | Restaurants, Coffee, Fast Food |
| Entertainment | Streaming, Movies, Games, Hobbies |
| Healthcare | Doctor, Pharmacy, Dental, Vision |
| Shopping | Clothing, Electronics, Home Goods |
| Subscriptions | Software, Memberships |
| Other | Gifts, Donations, Fees, Misc |

---

## Tech Stack

| Concern | Package | Purpose |
|---|---|---|
| Database | `drift` + `sqlite3_flutter_libs` | Type-safe SQLite |
| Code Generation | `drift_dev` + `build_runner` | Generate drift code |
| File Picking | `file_picker` | PDF/CSV/image import |
| CSV Parsing | `csv` | Statement CSV import |
| PDF Text (Phase 2) | `pdfx` | PDF statement text extraction |
| UUID | `uuid` | Generate unique IDs |
| Formatting | `intl` | Currency/date display |
| Path | `path_provider` | App directory access |

State management, navigation, image cropping, and theming all use Flutter built-ins. No external packages for those.

---

## Development Phases

### Phase 1 — Foundation
- Flutter project scaffolding (Windows)
- drift database setup with all tables
- Plain Dart model classes
- Repository layer
- App theme + navigation shell (4 tabs)

### Phase 2 — Categories
- Category CRUD screens
- Default category seeding
- Sub-category support
- PayeeRule management UI

### Phase 3 — Receipts
- Image file picker + drag-and-drop
- Receipt list screen with status filtering
- Receipt detail / annotation screen
- Custom image cropping widget
- Receipt item entry (name, price, taxable, category)
- Foreign currency checkbox + CAD amount input
- Receipt status progression

### Phase 4 — Statements
- CSV upload + column mapping UI
- CsvProfile save/load
- Statement list + detail screens
- Manual category assignment per line
- PayeeRule auto-categorization on import
- Receipt ↔ Statement line manual linking

### Phase 5 — Reports
- Monthly spending by category (simple list/card view)
- Drill-down into category details
- Date range filtering
- Tax paid summary

### Phase 6 — Polish
- Data export/backup (DB + images as zip)
- Receipt ↔ Statement auto-matching suggestions
- Search across receipts and statements
- PDF statement import via `pdfx`
