"""
Approach #2 evaluation: thresholding + connected components (pure PIL).
Downsamples to ≤800px before processing so it's fast on phone photos.

Usage:  python3.10 eval_bbox.py
"""

import json, sqlite3, statistics
from pathlib import Path
from PIL import Image, ImageFilter

DB_PATH = "/mnt/c/Users/stephen/Documents/BeanBudget/database/bean_budget.db"
WORK_SIZE = 800  # max dimension for detection (speed)

# ── helpers ───────────────────────────────────────────────────────────────────

def to_wsl(win_path):
    p = win_path.replace("\\", "/")
    if len(p) >= 2 and p[1] == ":":
        return f"/mnt/{p[0].lower()}{p[2:]}"
    return p

def quad_aabb(pts):
    xs = [p["x"] for p in pts]; ys = [p["y"] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)

def iou(a, b):
    ix0=max(a[0],b[0]); iy0=max(a[1],b[1])
    ix1=min(a[2],b[2]); iy1=min(a[3],b[3])
    inter=max(0,ix1-ix0)*max(0,iy1-iy0)
    ua=(a[2]-a[0])*(a[3]-a[1]); ub=(b[2]-b[0])*(b[3]-b[1])
    d=ua+ub-inter
    return inter/d if d>0 else 0.0

def corner_err(det, man):
    dc=[(det[0],det[1]),(det[2],det[1]),(det[2],det[3]),(det[0],det[3])]
    mc=[(man[0],man[1]),(man[2],man[1]),(man[2],man[3]),(man[0],man[3])]
    return statistics.mean(((dx-mx)**2+(dy-my)**2)**0.5 for (dx,dy),(mx,my) in zip(dc,mc))

def otsu(img):
    """Return Otsu threshold value for a greyscale PIL image."""
    hist = img.histogram()  # 256 buckets, PIL built-in, very fast
    total = img.width * img.height
    g_mean = sum(i*hist[i] for i in range(256)) / total
    best_t, best_var, w0, cum = 0, -1.0, 0.0, 0.0
    for i in range(256):
        w0 += hist[i] / total
        w1 = 1.0 - w0
        if w0 == 0 or w1 == 0: continue
        cum += i * hist[i] / total
        mu0 = cum / w0; mu1 = (g_mean - cum) / w1
        var = w0 * w1 * (mu0 - mu1) ** 2
        if var > best_var:
            best_var, best_t = var, i
    return best_t

# ── detection ─────────────────────────────────────────────────────────────────

def detect_bbox(path):
    img = Image.open(path).convert("L")

    # Downsample for speed
    scale = WORK_SIZE / max(img.size)
    if scale < 1.0:
        small = img.resize((int(img.width*scale), int(img.height*scale)), Image.LANCZOS)
    else:
        small = img
    w, h = small.size

    # Blur + Otsu threshold → bright binary image
    blurred = small.filter(ImageFilter.GaussianBlur(radius=2))
    t = otsu(blurred)
    # point() is a fast C loop in PIL
    binary = blurred.point(lambda v: 255 if v > t else 0)

    # Morphological close via MaxFilter (dilation) + MinFilter (erosion)
    # Size ~5% of image width, kept small because we're at 800px
    sz = max(5, min(31, int(w * 0.05))) | 1  # force odd
    dilated = binary.filter(ImageFilter.MaxFilter(sz))
    closed  = dilated.filter(ImageFilter.MinFilter(sz))

    # Bounding box of white region using PIL's getbbox on inverted image
    # (getbbox finds non-zero pixels; invert so bright=foreground)
    bbox = closed.getbbox()  # (left, top, right, bottom) in px, or None
    if bbox is None:
        return None

    c0, r0, c1, r1 = bbox
    # Reject if it covers essentially the whole image
    if (c1-c0)*(r1-r0) / (w*h) > 0.97:
        return None

    return c0/w, r0/h, c1/w, r1/h

# ── main ──────────────────────────────────────────────────────────────────────

def main():
    con = sqlite3.connect(DB_PATH)
    rows = con.execute("""
        SELECT i.file_path, r.crop_points
        FROM receipts r
        JOIN images i ON r.image_id = i.id
        WHERE r.crop_points IS NOT NULL
    """).fetchall()
    con.close()

    print(f"\n  {'Image':<24} {'IoU':>6}  {'CornerErr':>9}  "
          f"{'Detected':>26}  Manual AABB")
    print("  " + "-"*105)

    ious, errs = [], []
    for win_path, crop_json in rows:
        wsl_path = to_wsl(win_path)
        name = Path(wsl_path).name[:24]
        if not Path(wsl_path).exists():
            print(f"  {name:<24}  MISSING"); continue

        cp  = json.loads(crop_json)
        man = quad_aabb([cp["tl"], cp["tr"], cp["br"], cp["bl"]])

        try:
            det = detect_bbox(wsl_path)
        except Exception as e:
            print(f"  {name:<24}  ERROR: {e}"); continue

        if det is None:
            print(f"  {name:<24}  NO DETECTION"); continue

        iou_v = iou(det, man)
        err_v = corner_err(det, man)
        ious.append(iou_v); errs.append(err_v)

        flag = "  " if iou_v >= 0.75 else "⚠ "
        print(f"  {flag}{name:<24} {iou_v:>6.3f}  {err_v:>9.4f}"
              f"  [{det[0]:.2f},{det[1]:.2f} → {det[2]:.2f},{det[3]:.2f}]"
              f"  [{man[0]:.2f},{man[1]:.2f} → {man[2]:.2f},{man[3]:.2f}]")

    if ious:
        print("  " + "-"*105)
        print(f"  {'MEAN':<26} {statistics.mean(ious):>6.3f}  {statistics.mean(errs):>9.4f}")
        print(f"  {'MEDIAN':<26} {statistics.median(ious):>6.3f}  {statistics.median(errs):>9.4f}")
        print(f"  {'MIN':<26} {min(ious):>6.3f}  {min(errs):>9.4f}")
        print(f"\n  n={len(ious)}")
        print(f"  IoU >= 0.80: {sum(v>=0.80 for v in ious)}/{len(ious)}")
        print(f"  IoU >= 0.70: {sum(v>=0.70 for v in ious)}/{len(ious)}")
        print(f"  IoU >= 0.60: {sum(v>=0.60 for v in ious)}/{len(ious)}")

if __name__ == "__main__":
    main()
