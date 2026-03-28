"""
Visualize the Canny edge output and detection result on a few images.
Saves debug images alongside the originals.

Usage:  python3.8 visualize_detection.py
"""
import json, sqlite3
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

DB_PATH = "/mnt/c/Users/stephen/Documents/BeanBudget/database/bean_budget.db"
OUT_DIR  = "/mnt/c/projects/bean_budget/scripts/debug_viz"
WORK_SIZE = 800

# Images with known-bad manual crops — skip in visualization
EXCLUDE_STEMS = {"4d57279fef06"}

def to_wsl(p):
    p = p.replace("\\", "/")
    if len(p) >= 2 and p[1] == ":":
        return f"/mnt/{p[0].lower()}{p[2:]}"
    return p

Path(OUT_DIR).mkdir(exist_ok=True)

con = sqlite3.connect(DB_PATH)
rows = con.execute("""
    SELECT i.file_path, r.crop_points FROM receipts r
    JOIN images i ON r.image_id = i.id WHERE r.crop_points IS NOT NULL
""").fetchall()[:4]   # just first 4
con.close()

for win_path, crop_json in rows:
    wsl_path = to_wsl(win_path)
    if not Path(wsl_path).exists(): continue
    stem = Path(wsl_path).stem[:12]
    if stem in EXCLUDE_STEMS: continue

    pil = Image.open(wsl_path).convert("RGB")
    scale = WORK_SIZE / max(pil.size)
    if scale < 1.0:
        pil = pil.resize((int(pil.width*scale), int(pil.height*scale)), Image.LANCZOS)
    img = np.array(pil)
    h, w = img.shape[:2]

    gray    = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    med     = float(np.median(blurred))
    edges   = cv2.Canny(blurred, max(0, int(0.66*med)), min(255, int(1.33*med)))
    k       = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    dilated = cv2.dilate(edges, k, iterations=2)

    # HSV saturation mask
    hsv = cv2.cvtColor(img, cv2.COLOR_RGB2HSV)
    _, sat_mask = cv2.threshold(hsv[:,:,1], 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # Manual box
    cp = json.loads(crop_json)
    man_x0 = int(min(cp["tl"]["x"], cp["bl"]["x"]) * w)
    man_y0 = int(min(cp["tl"]["y"], cp["tr"]["y"]) * h)
    man_x1 = int(max(cp["tr"]["x"], cp["br"]["x"]) * w)
    man_y1 = int(max(cp["bl"]["y"], cp["br"]["y"]) * h)

    # Save: original + manual box | edges | sat mask — side by side
    orig_bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    cv2.rectangle(orig_bgr, (man_x0, man_y0), (man_x1, man_y1), (0, 255, 0), 2)

    edges_3ch  = cv2.cvtColor(dilated, cv2.COLOR_GRAY2BGR)
    sat_3ch    = cv2.cvtColor(sat_mask, cv2.COLOR_GRAY2BGR)

    panel = np.hstack([orig_bgr, edges_3ch, sat_3ch])
    out = f"{OUT_DIR}/{stem}_debug.jpg"
    cv2.imwrite(out, panel)
    print(f"Saved {out}")
