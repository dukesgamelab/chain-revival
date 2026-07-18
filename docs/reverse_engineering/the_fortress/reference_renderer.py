#!/usr/bin/env python3
"""Chain Revival — reference map renderer.

This file IS the reproducible pipeline: everything it consumes (exact MBM decodes,
MDL hotspots, OIN map data) and every rule it applies (bake-time footing removal,
frame selection, floor art mapping, ground fill, underlay) is exportable to the
Cursor package as assets + manifest metadata. No temporary or internal-only inputs.

Usage: render_map.py <decoded_map.oin> <out_prefix> [camera_step 0..3]
"""
import struct, re, json, sys
import numpy as np
from PIL import Image, ImageDraw

MBM = 'cochost/updates/models/cocsc/magall.MBm'
MDL = 'cochost/cocSc.MDL'

# ---------------- exact MBM decode (all three archive formats) ----------------
_d = open(MBM, 'rb').read()
_de = struct.unpack_from('<I', _d, 4)[0]
_pal = np.frombuffer(_d[_de-1024:_de], dtype=np.uint8).reshape(256, 4)[:, [2, 1, 0]]
_pos, _ents = 12, []
while _pos < _de:
    _e = _d.index(b'\x00', _pos+1)
    _nm = _d[_pos+1:_e]
    if not re.fullmatch(br'[ -~]+', _nm):
        break
    _ents.append((_nm.decode(), struct.unpack_from('<I', _d, _e+1)[0]))
    _pos = _e + 5
_ents = [x for x in _ents if 0 < x[1] < len(_d)]
_ents.sort(key=lambda x: x[1])
_names = [n for n, _ in _ents]

def decode_exact(name):
    if name not in _names:
        return None
    i = _names.index(name)
    off = _ents[i][1]
    end = _ents[i+1][1] if i+1 < len(_ents) else len(_d)
    b = _d[off:end]
    if len(b) >= 4:
        w, h = b[0], b[1]
        ns = struct.unpack_from('<H', b, 2)[0]
        hdr = 4 + ns*3
        if w and h and hdr <= len(b) and hdr + sum(b[4+k*3+2] for k in range(ns)) == len(b):
            A = np.full((h, w), -1, np.int16); p, q = 4, hdr
            for _ in range(ns):
                y, x, l = b[p], b[p+1], b[p+2]; p += 3
                A[h-1-y, x:x+l] = np.frombuffer(b[q:q+l], np.uint8); q += l
            return A
    if len(b) >= 8:
        w, h, ns, _pad = struct.unpack_from('<HHHH', b, 0)
        hdr = 8 + ns*6
        if 0 < w < 4096 and 0 < h < 4096 and hdr <= len(b):
            try:
                tot = hdr + sum(struct.unpack_from('<HHH', b, 8+k*6)[2] for k in range(ns))
            except struct.error:
                tot = -1
            if tot == len(b):
                A = np.full((h, w), -1, np.int16); p, q = 8, hdr
                for _ in range(ns):
                    y, x, l = struct.unpack_from('<HHH', b, p); p += 6
                    A[h-1-y, x:x+l] = np.frombuffer(b[q:q+l], np.uint8); q += l
                return A
    if len(b) >= 12:
        w, h, n = struct.unpack_from('<III', b, 0)
        if 12 + n == len(b) and w*h == n:
            A = np.frombuffer(b[12:12+n], np.uint8).reshape(h, w)[::-1].astype(np.int16)
            return np.where(A == A[0, 0], -1, A)
    return None

# ------------- bake-time footing removal (documented preprocessing) -----------
# A column is kept iff its topmost opaque pixel lies above the ground-diamond band
# (canvas row < 56) OR its opaque height exceeds 22 px (protects window/door frames).
# Deterministic; applied identically when baking the Cursor sprite PNGs.
def to_rgba(A, wall=False):
    h, w = A.shape
    r = np.zeros((h, w, 4), np.uint8)
    m = A >= 0
    r[m, :3] = _pal[A[m]]
    r[m, 3] = 255
    if wall and h >= 90:
        keep = np.zeros(w, bool)
        for x in range(w):
            col = np.where(m[:, x])[0]
            if len(col) and (col.min() < 56 or (col.max()-col.min()) > 22):
                keep[x] = True
        r[:, ~keep] = 0
    return r

# ------------------------- MDL sprite records --------------------------------
_mdl = open(MDL, 'rb').read()
_recs = {}
for m in re.finditer(br'(..)\x00 g\x00\xff\xff\x00 \x01\x00(.)', _mdl, re.DOTALL):
    oid = int.from_bytes(m.group(1), 'little'); ln = m.group(2)[0]
    nm = _mdl[m.end():m.end()+ln]
    if not re.fullmatch(br'[0-9A-Za-z_\-]+\.(bmp|BMP)', nm):
        continue
    t = _mdl[m.end()+ln:m.end()+ln+16]
    hx = hy = None
    if t[:4] == b'\x02\x00\x00\x00' and t[4:6] == b'\x09\x00' and t[8:10] == b'\x0a\x00':
        hx = struct.unpack('<h', t[6:8])[0]; hy = struct.unpack('<h', t[10:12])[0]
    _recs[oid] = (nm.decode().upper(), hx if hx is not None else -50, hy if hy is not None else -73)
FRAMES = {}
for m in re.finditer(br'bmp - (\w{2,8}) static mag 8 frame 0 (\S{1,2})(..)\x00', _mdl):
    oid = int.from_bytes(m.group(3), 'little')
    if oid in _recs:
        FRAMES.setdefault(m.group(1).decode().upper(), {})[m.group(2).decode()] = _recs[oid]

LETTERS4 = ['e', 's', 'w', 'n']
WALLISH = {'IWWL','RIHW','LIHW','SWAL','WWAL','WH01','WH02','SWIN','WWIN','IWCR','IWCL','WCOR',
           'SCOR','SICR','WICR','WWAR','WWAQ','SWAQ','SWAR','WWAI','WH11','WH00','SDOR','WDOR'}
FLOORS = {'SFLO','WFLO','SFR2'}
SUBST  = {'TR02': 'TR01'}
IRREG  = {('LIHW','e'): 's', ('LIHW','w'): 's', ('ASID','s'): 'se'}   # irregular_fallbacks.json

_cache = {}
def sprite(code, letter):
    key = (code, letter)
    if key in _cache:
        return _cache[key]
    r = FRAMES.get(code, {}).get(letter)
    v = None
    if r:
        A = decode_exact(r[0])
        if A is not None and (A >= 0).sum() > 0:
            import numpy as _np
            if len(_np.unique(A[A >= 0])) > 2:   # solid-color frames are placeholders
                rr = to_rgba(A, wall=(code in WALLISH))
                if rr[..., 3].sum() > 0:
                    v = (Image.fromarray(rr, 'RGBA'), r[1], r[2])
    _cache[key] = v
    return v

# frame selection: view-relative facet, camera-adjusted. The projection convention
# constant PROJ=0 pairs with this renderer's screen mapping; the composed result at
# camera 0 equals the previously footage-verified reference. (Engine-equivalent under
# the engine's own mirrored ConvertToScreen convention.)
def pick(code, direction, camera):
    c = SUBST.get(code, code)
    # binary-recovered: slot = ((Direction - 90*camera + 45) mod 360) / 90, files [e,s,w,n]
    slot = (((direction - 90*camera) % 360) + 45) % 360 // 90
    letter = LETTERS4[slot]
    if (c, letter) in IRREG:
        letter = IRREG[(c, letter)]
    v = sprite(c, letter)
    if v is None:  # frame absent from archive (e.g. TA03 w): same-diagonal partner
        v = sprite(c, LETTERS4[(slot+2) % 4])
    if v is None:
        for l in LETTERS4:
            v = sprite(c, l)
            if v:
                break
    return v

# floors render with the flat tan frames (exported as FLOOR_TAN_* in the package;
# footage-verified display mapping, recorded in the manifest floors_rule)
_tanS = Image.fromarray(to_rgba(decode_exact('8SFL5S7A.BMP')), 'RGBA')
_tanW = Image.fromarray(to_rgba(decode_exact('8WFL5S7A.BMP')), 'RGBA')
FLOOR_IMG = {'SFLO': _tanS, 'WFLO': _tanW, 'SFR2': _tanS}
_tanS_a = np.array(_tanS); _tanW_a = np.array(_tanW)

# ground: GRS family minus color outliers (deterministic filter), well-mixed hash
_target = np.array([143, 143, 108])
GRS = []
for n in _names:
    if re.fullmatch(r'8GRS\d_\dA\.BMP', n):
        A = decode_exact(n)
        mm = A >= 0
        if np.abs(_pal[A[mm]].mean(axis=0) - _target).sum() < 40:
            GRS.append(Image.fromarray(to_rgba(A), 'RGBA'))

def h2(cx, cy, n):
    x = (cx*73856093) ^ (cy*19349663) ^ ((cx+cy)*83492791)
    x = (x ^ (x >> 13)) * 0x5bd1e995
    return (x ^ (x >> 15)) % n

# half-diamond floor underlay toward floor neighbours
_H, _W = _tanS_a.shape[:2]
_yy, _xx = np.mgrid[0:_H, 0:_W]
_DIRS = {(0, 1): (-31, 16), (1, 0): (31, 16), (0, -1): (31, -16), (-1, 0): (-31, -16)}
def half_img(wood, nbrs):
    base = _tanW_a if wood else _tanS_a
    mask = np.zeros((_H, _W), bool)
    for nb in nbrs:
        dx, dy = _DIRS[nb]
        mask |= ((_xx-52.0)*dx + (_yy-74.0)*dy) > 0
    out = base.copy(); out[~mask] = 0
    return Image.fromarray(out, 'RGBA')

def render(map_oin, out_prefix, camera=0):
    tiles = {}
    for line in open(map_oin, encoding='latin-1'):
        m = re.match(r'ADDPROP,((?:_HG_)?TerrainTile ocn# \d+|TerrainLabel ocn# \d+),([^,]+),(.*)$',
                     line.rstrip())
        if m:
            o, k, v = m.groups()
            tiles.setdefault(o, {})[k] = v.rstrip()
    T, labels = [], []
    for name, t in tiles.items():
        if name.startswith('TerrainLabel'):
            if 'x' in t and 'y' in t:
                labels.append((int(t['x']), int(t['y']), t.get('Text', '').strip()))
            continue
        if 'x' not in t or 'y' not in t:
            continue
        code = t.get('Image', '').replace('img - ', '').replace(' static', '').upper()
        img1 = t.get('Image1', '').replace('img - ', '').replace(' static', '').upper() or None
        T.append({'x': int(t['x']), 'y': int(t['y']), 'img': code, 'img1': img1,
                  'dir': int(t.get('Direction', '0') or 0), 'z': int(t.get('z', '0') or 0)})
    floorset = {(t['x'], t['y']): t['img'] for t in T if t['img'] in FLOORS}
    xs = [t['x'] for t in T]; ys = [t['y'] for t in T]
    N = max(max(xs), max(ys))
    def view(x, y):
        for _ in range(camera % 4):
            x, y = y, N - x
        return x, y
    x0, x1 = min(xs)-6, max(xs)+6
    y0, y1 = min(ys)-6, max(ys)+6
    # bounds in view space
    corners = [view(a, b) for a in (x0, x1) for b in (y0, y1)]
    vx0 = min(c[0] for c in corners); vx1 = max(c[0] for c in corners)
    vy0 = min(c[1] for c in corners); vy1 = max(c[1] for c in corners)
    SX, SY = 31, 16
    ox = (vy1+1)*SX + 120
    W = (vx1+vy1+4)*SX + 240; H = (vx1+vy1+4)*SY + 300
    img = Image.new('RGBA', (W, H), (122, 120, 89, 255))
    def pt(vx, vy):
        return ox + (vx-vy)*SX, 140 + (vx+vy)*SY
    for cy in range(y0, y1+1):
        for cx in range(x0, x1+1):
            vx, vy = view(cx, cy)
            px, py = pt(vx, vy)
            img.alpha_composite(GRS[h2(cx, cy, len(GRS))], (px-50, py-73))
    for (x, y), code in sorted(floorset.items(), key=lambda p: sum(view(*p[0]))):
        px, py = pt(*view(x, y))
        img.alpha_composite(FLOOR_IMG[code], (px-50, py-73))
    # engine's explicit under-images first (Image1 property = original mechanism)
    UNDER = {'WFLO': _tanW, 'SFLO': _tanS, 'SFL5': _tanS, 'WFL5': _tanW, 'SFR2': _tanS}
    for t in T:
        if t.get('img1') in UNDER:
            px, py = pt(*view(t['x'], t['y']))
            img.alpha_composite(UNDER[t['img1']], (px-50, py-73))
    for t in T:
        if t['img'] not in WALLISH:
            continue
        x, y = t['x'], t['y']
        nbrs = []; wood = None
        for nb in [(0, 1), (1, 0), (0, -1), (-1, 0)]:
            p = (x+nb[0], y+nb[1])
            if p in floorset:
                nbrs.append(nb)
                if wood is None:
                    wood = floorset[p] == 'WFLO'   # first neighbour decides tint (reference behaviour)
        if nbrs:
            px, py = pt(*view(x, y))
            img.alpha_composite(half_img(wood, nbrs), (px-50, py-73))
    T.sort(key=lambda t: (t['z'], sum(view(t['x'], t['y']))))
    for t in T:
        if t['img'] == 'NEAR' or t['img'] in FLOORS:
            continue
        v = pick(t['img'], t['dir'], camera)
        if v is None:
            continue
        im, hx, hy = v
        px, py = pt(*view(t['x'], t['y']))
        img.alpha_composite(im, (px+hx, py+hy))
    dr = ImageDraw.Draw(img)
    for lx, ly, txt in labels:
        if not txt:
            continue
        px, py = pt(*view(lx, ly))
        dr.text((px+1, py+1), txt, fill=(0, 0, 0, 255))
        dr.text((px, py), txt, fill=(255, 255, 0, 255))
    img.convert('RGB').save(out_prefix + '_full.png')
    sm = img.convert('RGB'); sm.thumbnail((1600, 1600))
    sm.save(out_prefix + '_small.png')
    return out_prefix + '_full.png'

if __name__ == '__main__':
    oin = sys.argv[1] if len(sys.argv) > 1 else 'decoded/TheFortress_map.oin'
    pref = sys.argv[2] if len(sys.argv) > 2 else 'fortress_ref'
    cam = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    print(render(oin, pref, cam))
