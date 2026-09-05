#!/usr/bin/env python3
"""Bakes the floor textures into ../CrazySkilledTrucker/Floor and a composed preview.

    ../../..scratch/venv/bin/python make_floor.py      # needs numpy and Pillow

Base tile: ambientCG Asphalt004 (CC0), fetched into cache/ on first run, darkened for night.
Everything else is generated: a tileable grime layer, oil stains, cracks, tyre marks,
puddles and an eroded paint line. preview.png composes them over a mock of the lot so the
look can be judged before any of it reaches the iPad.
"""
import io, math, os, random, sys, urllib.request, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'cache')
OUT = os.path.join(HERE, '..', 'CrazySkilledTrucker', 'Floor')
TILE_URL = 'https://ambientcg.com/get?file=Asphalt004_1K-JPG.zip'
TILE_NAME = 'Asphalt004'
random.seed(4)
rng = np.random.default_rng(4)


def fetch_tile():
	folder = os.path.join(CACHE, TILE_NAME)
	color = os.path.join(folder, TILE_NAME + '_1K-JPG_Color.jpg')
	if not os.path.exists(color):
		os.makedirs(folder, exist_ok=True)
		print('downloading', TILE_URL)
		data = urllib.request.urlopen(TILE_URL, timeout=120).read()
		zipfile.ZipFile(io.BytesIO(data)).extractall(folder)
	return Image.open(color).convert('RGB')


def save(img, name, **kw):
	path = os.path.join(OUT, name)
	img.save(path, **kw)
	print('%-18s %5dx%-5d %7d bytes' % (name, img.width, img.height, os.path.getsize(path)))


# --- base tile: night asphalt ------------------------------------------------------

def asphalt(tile):
	a = np.asarray(tile.resize((512, 512), Image.LANCZOS)).astype(np.float32) / 255
	grey = a.mean(axis=2, keepdims=True)
	a = grey * 0.7 + a * 0.3							# most of the colour out
	a = (a - a.mean()) * 1.6 + 0.30					# more contrast in the mottling, darker overall
	tint = np.array([0.78, 0.84, 1.0])				# cold night
	a = np.clip(a * tint, 0, 1)
	return Image.fromarray((a * 255).astype(np.uint8))


# --- tileable low-frequency grime, from a periodic spectrum ------------------------

def periodic_noise(size, falloff, seed):
	r = np.random.default_rng(seed)
	fy = np.fft.fftfreq(size)[:, None]
	fx = np.fft.fftfreq(size)[None, :]
	f = np.sqrt(fx * fx + fy * fy)
	f[0, 0] = 1
	spectrum = (r.standard_normal((size, size)) + 1j * r.standard_normal((size, size))) / (f ** falloff)
	spectrum[0, 0] = 0
	n = np.real(np.fft.ifft2(spectrum))
	n = (n - n.min()) / (n.max() - n.min())
	return n


def grime():
	n = periodic_noise(512, 2.2, 11)
	n = 0.55 + 0.45 * n									# multiply layer: 0.55 .. 1.0
	return Image.fromarray((n * 255).astype(np.uint8), 'L')


# --- decals ----------------------------------------------------------------------

def stain(size, seed):
	r = random.Random(seed)
	img = Image.new('L', (size, size), 0)
	d = ImageDraw.Draw(img)
	cx, cy = size / 2, size / 2
	for _ in range(r.randint(3, 6)):
		rx, ry = r.uniform(size * 0.12, size * 0.32), r.uniform(size * 0.10, size * 0.28)
		ox, oy = r.uniform(-size * 0.12, size * 0.12), r.uniform(-size * 0.12, size * 0.12)
		layer = Image.new('L', (size, size), 0)
		ImageDraw.Draw(layer).ellipse([cx + ox - rx, cy + oy - ry, cx + ox + rx, cy + oy + ry], fill=r.randint(120, 220))
		layer = layer.filter(ImageFilter.GaussianBlur(r.uniform(size * 0.02, size * 0.07)))
		img = ImageChops.lighter(img, layer)
	alpha = np.asarray(img).astype(np.float32) / 255
	grain = periodic_noise(size, 1.0, seed)
	alpha = np.clip(alpha * (0.7 + 0.6 * grain) * 1.1, 0, 1)
	rgb = np.zeros((size, size, 3), np.uint8)
	rgb[..., 0], rgb[..., 1], rgb[..., 2] = 14, 10, 8
	out = np.dstack([rgb, (alpha * 255).astype(np.uint8)])
	return Image.fromarray(out, 'RGBA')


def crack(w, h, seed):
	r = random.Random(seed)
	img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)

	def walk(x, y, ang, home, length, width):
		pts = [(x, y)]
		for _ in range(length):
			ang += r.uniform(-0.35, 0.35) + (home - ang) * 0.25		# wander, pulled back to its line
			x += math.cos(ang) * r.uniform(3, 7)
			y += math.sin(ang) * r.uniform(3, 7)
			if not (0 <= x < w and 0 <= y < h):
				break
			pts.append((x, y))
		for i in range(len(pts) - 1):
			t = i / max(1, len(pts) - 1)
			wid = max(1, width * (1 - 0.7 * t))
			d.line([pts[i], pts[i + 1]], fill=(0, 0, 0, int(240 - 100 * t)), width=int(round(wid)))
		return pts

	main = walk(4, h / 2 + r.uniform(-h * 0.15, h * 0.15), 0, 0, int(w / 4), 4.5)
	for _ in range(r.randint(2, 4)):
		p = r.choice(main[len(main) // 5: 4 * len(main) // 5])
		side = r.choice([-1, 1])
		walk(p[0], p[1], side * r.uniform(0.7, 1.3), side * 0.9, r.randint(6, 16), 2.4)
	light = ImageChops.offset(img, 1, 1)
	light = Image.fromarray(np.dstack([np.full((h, w, 3), 255, np.uint8), (np.asarray(light)[..., 3] * 0.14).astype(np.uint8)]), 'RGBA')
	return Image.alpha_composite(light, img)


def tyre(w, h, seed):
	r = random.Random(seed)
	noise = periodic_noise(max(w, h), 0.6, seed)[:h, :w]
	x = np.linspace(0, 1, w)[None, :]
	fade = np.clip(np.minimum(x, 1 - x) * 5, 0, 1)		# ends fade out
	y = np.arange(h)[:, None]
	bands = np.zeros((h, w), np.float32)
	for centre in (h * 0.30, h * 0.70):					# dual tyres of one axle side
		bands += np.exp(-((y - centre) ** 2) / (2 * (h * 0.075) ** 2))
	alpha = np.clip(bands * fade * (0.35 + 0.65 * noise) * 0.55, 0, 1)
	rgb = np.zeros((h, w, 3), np.uint8)
	rgb[..., 0], rgb[..., 1], rgb[..., 2] = 8, 8, 10
	return Image.fromarray(np.dstack([rgb, (alpha * 255).astype(np.uint8)]), 'RGBA')


def puddle(w, h, seed):
	r = random.Random(seed)
	mask = Image.new('L', (w, h), 0)
	d = ImageDraw.Draw(mask)
	for _ in range(r.randint(3, 5)):
		rx, ry = r.uniform(w * 0.18, w * 0.36), r.uniform(h * 0.18, h * 0.36)
		ox, oy = r.uniform(-w * 0.1, w * 0.1), r.uniform(-h * 0.1, h * 0.1)
		d.ellipse([w / 2 + ox - rx, h / 2 + oy - ry, w / 2 + ox + rx, h / 2 + oy + ry], fill=255)
	mask = mask.filter(ImageFilter.GaussianBlur(3)).point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.GaussianBlur(1.2))
	m = np.asarray(mask).astype(np.float32) / 255
	sheen = periodic_noise(max(w, h), 1.6, seed + 7)[:h, :w]
	sheen = np.clip((sheen - 0.55) * 2.5, 0, 1)			# only the brightest patches shine
	dark = m * 0.45
	shine = m * sheen * 0.35
	alpha = np.clip(dark + shine, 0, 1)
	# colour goes from wet-black to a cold sky reflection where it shines
	mix = np.where(alpha > 0, shine / np.maximum(alpha, 1e-6), 0)[..., None]
	rgb = (np.array([6, 8, 12]) * (1 - mix) + np.array([150, 175, 215]) * mix).astype(np.uint8)
	return Image.fromarray(np.dstack([rgb, (alpha * 255).astype(np.uint8)]), 'RGBA')


def paint_line(w, h, seed):
	n = periodic_noise(w, 1.2, seed)[:h, :w]
	y = np.arange(h)[:, None]
	edge = np.clip((np.minimum(y, h - 1 - y) + 0.5) / 2.5, 0, 1)		# soft edge rows
	alpha = np.clip((n - 0.32) * 2.2, 0, 1) * edge * 0.85
	rgb = np.full((h, w, 3), 255, np.uint8)
	return Image.fromarray(np.dstack([rgb, (alpha * 255).astype(np.uint8)]), 'RGBA')


# --- preview: the layer stack over a mock lot ---------------------------------------

def preview(tile, grime_img, decals):
	S = 2											# device pixels per canvas unit
	W, H = 850 * S, 650 * S
	base = Image.new('RGB', (W, H))
	t = tile.resize((128 * S, 128 * S))
	for gx in range(0, W, 128 * S):
		for gy in range(0, H, 128 * S):
			base.paste(t.rotate(90 * random.randint(0, 3)), (gx, gy))
	g = grime_img.resize((W, H), Image.BILINEAR).convert('RGB')
	base = ImageChops.multiply(base, Image.blend(Image.new('RGB', (W, H), (255, 255, 255)), g, 0.6))
	canvas = base.convert('RGBA')

	def stamp(img, x, y, scale, angle, alpha):
		im = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS).rotate(angle, expand=True, resample=Image.BICUBIC)
		if alpha < 1:
			a = im.split()[3].point(lambda v: int(v * alpha))
			im.putalpha(a)
		canvas.alpha_composite(im, (int(x - im.width / 2), int(y - im.height / 2)))

	# rough lot geometry, in canvas units: rows at x=150 and x=700, lane between, 9 slots
	rows, pitch, first = (150, 700), 40, 90
	for _ in range(14):
		stamp(random.choice(decals['crack']), random.uniform(0, W), random.uniform(0, H), random.uniform(0.5, 1.0), random.uniform(0, 360), random.uniform(0.5, 0.9))
	for rx in rows:
		mouth = rx + (85 if rx < 425 else -85)					# where the cab stands, toward the lane
		for i in range(9):
			y = (first + pitch * i) * S
			if random.random() < 0.6:
				stamp(random.choice(decals['stain']), (mouth + random.uniform(-25, 15)) * S, y + random.uniform(-10, 10) * S, random.uniform(0.3, 0.55), random.uniform(0, 360), random.uniform(0.7, 1.0))
	for _ in range(6):
		stamp(random.choice(decals['stain']), random.uniform(300, 550) * S, random.uniform(60, 600) * S, random.uniform(0.25, 0.5), random.uniform(0, 360), random.uniform(0.5, 0.9))
	for _ in range(12):
		toward_left = random.random() < 0.5
		x = random.uniform(250, 600) * S
		angle = 90 + (random.uniform(15, 45) * (1 if toward_left else -1)) * random.choice([1, -1])
		stamp(random.choice(decals['tyre']), x, random.uniform(80, 600) * S, random.uniform(0.5, 1.0), angle, random.uniform(0.35, 0.7))
	for _ in range(5):
		stamp(random.choice(decals['tyre']), random.uniform(380, 470) * S, random.uniform(80, 600) * S, random.uniform(0.8, 1.2), 90 + random.uniform(-6, 6), random.uniform(0.3, 0.6))
	for _ in range(5):
		stamp(random.choice(decals['puddle']), random.uniform(0, W), random.uniform(0, H), random.uniform(0.6, 1.3), random.uniform(0, 360), 1)
	for rx in rows:
		for i in range(10):
			y = (first + pitch * (i - 0.5)) * S
			stamp(decals['line'], rx * S, y, 1.0, random.choice([0, 180]), random.uniform(0.45, 0.8))
	# mock trucks so contrast can be judged
	d = ImageDraw.Draw(canvas)
	cabs = [(220, 40, 40), (60, 130, 245), (245, 160, 10), (16, 186, 130), (100, 100, 245)]
	for rx in rows:
		for i in range(9):
			if rx == 150 and i == 4:
				continue
			y = (first + pitch * i) * S
			d.rectangle([(rx - 64) * S, y - 13 * S, (rx + 36) * S, y + 13 * S], fill=(238, 240, 244))
			d.rectangle([(rx + 36) * S, y - 12 * S, (rx + 64) * S, y + 12 * S], fill=cabs[i % 5])
	# sodium lamps
	glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
	gd = ImageDraw.Draw(glow)
	for (lx, ly, rad) in ((150, 100, 200), (650, 100, 200), (400, 550, 240)):
		for k in range(40, 0, -1):
			r_ = rad * S * k / 40
			a = int(3 + 14 * (1 - k / 40) ** 2)
			gd.ellipse([lx * S - r_, ly * S - r_, lx * S + r_, ly * S + r_], fill=(255, 190, 80, a))
	canvas = Image.alpha_composite(canvas, glow)
	# vignette
	yy, xx = np.mgrid[0:H, 0:W]
	dist = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
	v = np.clip((dist - 0.55) / 0.75, 0, 1) ** 1.6 * 0.85
	vig = Image.fromarray(np.dstack([np.zeros((H, W, 3), np.uint8), (v * 255).astype(np.uint8)]), 'RGBA')
	canvas = Image.alpha_composite(canvas, vig)
	return canvas.convert('RGB')


if __name__ == '__main__':
	os.makedirs(OUT, exist_ok=True)
	tile = asphalt(fetch_tile())
	save(tile, 'asphalt.jpg', quality=85)
	gr = grime()
	save(gr, 'grime.jpg', quality=80)
	decals = {'stain': [], 'crack': [], 'tyre': [], 'puddle': [], 'line': None}
	for i in range(4):
		decals['stain'].append(stain(256, 100 + i)); save(decals['stain'][-1], 'stain%d.png' % (i + 1), optimize=True)
		decals['crack'].append(crack(512, 96, 200 + i)); save(decals['crack'][-1], 'crack%d.png' % (i + 1), optimize=True)
	for i in range(3):
		decals['tyre'].append(tyre(384, 48, 300 + i)); save(decals['tyre'][-1], 'tyre%d.png' % (i + 1), optimize=True)
	for i in range(2):
		decals['puddle'].append(puddle(256, 192, 400 + i)); save(decals['puddle'][-1], 'puddle%d.png' % (i + 1), optimize=True)
	decals['line'] = paint_line(1024, 12, 500)
	save(decals['line'], 'paintline.png', optimize=True)
	prev = preview(tile, gr, decals)
	prev.save(os.path.join(HERE, 'cache', 'floor_preview.png'))
	print('preview -> tools/cache/floor_preview.png')
