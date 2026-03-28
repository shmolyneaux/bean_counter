"""
Approach: Canny edge detection + contour finding to auto-detect receipt bbox.
Compared against manually set crop points in the DB.

Usage:  python3.8 eval_bbox_contour.py
"""

import json, sqlite3, statistics
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

DB_PATH = "/mnt/c/Users/stephen/Documents/BeanBudget/database/bean_budget.db"
WORK_SIZE = 800  # downsample longest edge to this for speed

# Images with known-bad manual crops in the DB — exclude from evaluation
EXCLUDE_STEMS = {"4d57279fef06"}

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

# ── detection ─────────────────────────────────────────────────────────────────

def detect_bbox_saturation(img, w, h):
    """
    Receipt paper is white/grey (low HSV saturation).
    Background (brown table, cardboard) has higher saturation.
    Threshold on S channel, take largest low-saturation blob.
    """
    hsv = cv2.cvtColor(img, cv2.COLOR_RGB2HSV)
    sat = hsv[:, :, 1]  # 0-255

    # Otsu threshold on saturation to separate white paper from coloured background
    _, mask = cv2.threshold(sat, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # Morphological close to fill holes in the receipt body (text chars punch holes)
    k = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 15))
    closed = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k, iterations=3)

    # Find connected components; take the largest with area > 5% of image
    num, labels, stats, _ = cv2.connectedComponentsWithStats(closed)
    min_area = 0.05 * w * h
    best = None
    for i in range(1, num):  # skip background label 0
        area = stats[i, cv2.CC_STAT_AREA]
        if area >= min_area:
            if best is None or area > stats[best, cv2.CC_STAT_AREA]:
                best = i

    if best is None:
        return None

    x  = stats[best, cv2.CC_STAT_LEFT]
    y  = stats[best, cv2.CC_STAT_TOP]
    cw = stats[best, cv2.CC_STAT_WIDTH]
    ch = stats[best, cv2.CC_STAT_HEIGHT]

    # Reject if essentially the whole image
    if cw * ch / (w * h) > 0.95:
        return None

    return x/w, y/h, (x+cw)/w, (y+ch)/h


def detect_bbox_canny(img, w, h):
    """
    Canny edge detection, take the largest solid contour.
    """
    gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    med = float(np.median(blurred))
    lo  = max(0,   int(0.66 * med))
    hi  = min(255, int(1.33 * med))
    edges = cv2.Canny(blurred, lo, hi)
    k = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    edges = cv2.dilate(edges, k, iterations=2)

    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    min_area = 0.05 * w * h
    candidates = []
    for c in contours:
        cx, cy, cw, ch = cv2.boundingRect(c)
        area = cw * ch
        if area < min_area:
            continue
        hull = cv2.convexHull(c)
        solidity = cv2.contourArea(hull) / area if area > 0 else 0
        candidates.append((area, solidity, cx, cy, cw, ch))

    if not candidates:
        return None

    solid = [c for c in candidates if c[1] > 0.5]
    _, _, cx, cy, cw, ch = max(solid or candidates, key=lambda c: c[0])
    return cx/w, cy/h, (cx+cw)/w, (cy+ch)/h


def detect_bbox(path):
    pil = Image.open(path).convert("RGB")
    scale = WORK_SIZE / max(pil.size)
    if scale < 1.0:
        pil = pil.resize((int(pil.width*scale), int(pil.height*scale)), Image.LANCZOS)
    img = np.array(pil)
    h, w = img.shape[:2]

    return detect_bbox_canny(img, w, h)

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
        if Path(wsl_path).stem[:12] in EXCLUDE_STEMS:
            print(f"  {name:<24}  EXCLUDED (bad manual crop)"); continue
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
