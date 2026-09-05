#!/usr/bin/env python3
"""Bakes the truck sprites into ../CrazySkilledTrucker/Trucks and a preview sheet.

    ../../..scratch/venv/bin/python make_trucks.py      # needs Pillow

Classic 2D, top-down, flat colour with a dark outline: one texture per part, the sprite
just rotates. The effort is in variety, not shading. Local frame: +x is forward, the
image is the collision box exactly, so nothing sticks out of it.

Files: trailer_L<livery>_<1|2>.png (two trailers per livery), cab_L<livery>.png,
trailer_player.png, cab_player.png (no front wheels: the game draws the steered pair).
"""
import os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'CrazySkilledTrucker', 'Trucks')
PX = 4												# pixels per world unit
TRAILER = (400, 108)								# 100 x 27 units
CAB = (112, 96)										# 28 x 24 units
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'
OUTLINE = (18, 16, 22, 240)
random.seed(9)

# name, base, accent, text colour, cab colour
LIVERIES = [
	('NORDFRACHT', (236, 238, 242), (30, 80, 190), (30, 80, 190), (30, 80, 190)),
	('TRANSALPINA', (222, 40, 45), (250, 250, 250), (255, 255, 255), (222, 40, 45)),
	('KÜHLTRANS', (240, 244, 248), (30, 170, 210), (20, 120, 170), (240, 244, 248)),
	('EURO EXPRESS', (240, 176, 20), (30, 30, 34), (30, 30, 34), (240, 176, 20)),
	('HANSA CARGO', (24, 86, 60), (250, 250, 250), (250, 250, 250), (24, 86, 60)),
	('BLUE LINE', (26, 60, 130), (250, 250, 250), (250, 250, 250), (26, 60, 130)),
	('SILO-TRANS', (196, 200, 208), (200, 60, 30), (200, 60, 30), (245, 245, 245)),
	('MAGNUM', (40, 40, 44), (240, 90, 20), (240, 90, 20), (40, 40, 44)),
]
TYPES_PER_LIVERY = [
	('box', 'curtain'), ('box', 'reefer'), ('reefer', 'box'), ('box', 'flatbed_tarp'),
	('curtain', 'container'), ('box', 'flatbed_pipes'), ('tanker', 'tanker'), ('curtain', 'container'),
]


def shade(c, k):
	return tuple(max(0, min(255, int(v * k))) for v in c[:3])


def luminance(c):
	return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def darker_of(a, b):
	return a if luminance(a) < luminance(b) else b


def font(size):
	return ImageFont.truetype(FONT, size)


def body(img, box, fill, radius=8, outline=OUTLINE, width=3):
	d = ImageDraw.Draw(img)
	d.rounded_rectangle(box, radius=radius, fill=fill + (255,), outline=outline, width=width)


def text_along(img, text, box, colour, max_h, angle=0):
	"""Bold name along the length, fitted into box (x0, y0, x1, y1)."""
	x0, y0, x1, y1 = box
	size = max_h
	while size > 8:
		f = font(size)
		bb = f.getbbox(text)
		if bb[2] - bb[0] <= (x1 - x0) and bb[3] - bb[1] <= (y1 - y0):
			break
		size -= 1
	layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
	ld = ImageDraw.Draw(layer)
	bb = f.getbbox(text)
	tx = (x0 + x1) / 2 - (bb[2] + bb[0]) / 2
	ty = (y0 + y1) / 2 - (bb[3] + bb[1]) / 2
	ld.text((tx, ty), text, font=f, fill=colour + (255,))
	if angle:
		layer = layer.rotate(angle, resample=Image.BICUBIC, center=((x0 + x1) / 2, (y0 + y1) / 2))
	img.alpha_composite(layer)


def lamps(d, w, h):
	# tail lamps at the rear (left edge), amber markers at the front (right edge)
	for y in (10, h - 18):
		d.rectangle([4, y, 9, y + 8], fill=(235, 40, 40, 255))
		d.rectangle([w - 10, y, w - 5, y + 8], fill=(255, 170, 40, 255))


def wheels(d, xs, w, h, wheel_w=16, wheel_h=9):
	for x in xs:
		for y in (5, h - 5 - wheel_h):
			d.rounded_rectangle([x, y, x + wheel_w, y + wheel_h], radius=3, fill=(24, 24, 28, 255))
			d.rectangle([x + 3, y + 3, x + wheel_w - 3, y + wheel_h - 3], fill=(70, 70, 76, 255))


# --- trailer types --------------------------------------------------------------------

def trailer_box(img, liv, corrugated=False):
	name, base, accent, textc, _ = liv
	w, h = img.size
	d = ImageDraw.Draw(img)
	body(img, [0, 0, w - 1, h - 1], base)
	# roof seams along the length, and lateral ribs
	for y in (h * 0.34, h * 0.66):
		d.line([(10, y), (w - 10, y)], fill=shade(base, 0.9) + (255,), width=2)
	step = 12 if corrugated else 30
	for x in range(28, w - 28, step):
		d.line([(x, 8), (x, h - 8)], fill=shade(base, 0.93 if corrugated else 0.9) + (255,), width=2)
	# rear doors: darker band with the split line
	d.rectangle([3, 3, 20, h - 4], fill=shade(base, 0.82) + (255,))
	d.line([(12, 6), (12, h - 6)], fill=shade(base, 0.6) + (255,), width=2)
	# accent stripe: a diagonal band near the front
	d.polygon([(w - 90, 3), (w - 70, 3), (w - 100, h - 4), (w - 120, h - 4)], fill=accent + (255,))
	d.polygon([(w - 64, 3), (w - 56, 3), (w - 86, h - 4), (w - 94, h - 4)], fill=accent + (255,))
	text_along(img, name, (40, 14, w - 130, h - 14), textc, 44)
	wheels(d, [40, 66], w, h)
	lamps(d, w, h)


def trailer_reefer(img, liv):
	name, base, accent, textc, _ = liv
	white = (244, 246, 250)
	w, h = img.size
	ink = darker_of(base, accent)
	trailer_box(img, (name, white, ink, ink, None))
	d = ImageDraw.Draw(img)
	# the refrigeration unit on the nose: a grey box with vent slits
	d.rounded_rectangle([w - 30, 12, w - 6, h - 12], radius=4, fill=(150, 154, 162, 255), outline=OUTLINE, width=2)
	for y in range(20, h - 18, 7):
		d.line([(w - 26, y), (w - 10, y)], fill=(90, 92, 98, 255), width=2)
	# snowflake-ish mark: a blue disc
	d.ellipse([w - 150, h - 30, w - 128, h - 8], fill=(60, 150, 230, 255))


def trailer_curtain(img, liv):
	name, base, accent, textc, _ = liv
	w, h = img.size
	d = ImageDraw.Draw(img)
	body(img, [0, 0, w - 1, h - 1], base, radius=6)
	# the roof is a lighter lengthwise panel; straps every 24 px
	d.rectangle([22, 10, w - 10, h - 10], fill=shade(base, 1.08) + (255,))
	for x in range(34, w - 12, 24):
		d.line([(x, 8), (x, h - 8)], fill=shade(base, 0.72) + (255,), width=3)
	d.line([(22, h / 2), (w - 10, h / 2)], fill=shade(base, 0.85) + (255,), width=2)
	d.rectangle([3, 3, 20, h - 4], fill=shade(base, 0.8) + (255,))
	d.polygon([(w - 60, 3), (w - 44, 3), (w - 70, h - 4), (w - 86, h - 4)], fill=accent + (255,))
	text_along(img, name, (36, 16, w - 96, h - 16), textc, 40)
	wheels(d, [40, 66], w, h)
	lamps(d, w, h)


def trailer_flatbed(img, liv, load):
	name, base, accent, textc, _ = liv
	w, h = img.size
	d = ImageDraw.Draw(img)
	bed = (96, 92, 84)
	body(img, [0, 0, w - 1, h - 1], bed, radius=5)
	for y in range(9, h - 8, 9):									# planks
		d.line([(6, y), (w - 6, y)], fill=shade(bed, 0.82) + (255,), width=1)
	d.rectangle([w - 26, 6, w - 6, h - 7], fill=(60, 58, 54, 255))		# headboard
	if load == 'tarp':
		tarp = base if luminance(base) > 60 else accent
		d.rounded_rectangle([36, 8, w - 40, h - 9], radius=14, fill=tarp + (255,), outline=shade(tarp, 0.6) + (255,), width=2)
		for x in range(60, w - 50, 34):									# ropes over the tarp
			d.line([(x, 6), (x + 6, h - 6)], fill=shade(tarp, 0.55) + (255,), width=2)
		text_along(img, name, (60, 20, w - 70, h - 20), darker_of(base, accent) if tarp == base else shade(tarp, 1.6), 30)
	else:
		colours = [(130, 132, 138), (170, 172, 178), (110, 112, 118), (150, 152, 158), (125, 128, 134)]
		top, gap = 10, (h - 20) / 5
		for i, c in enumerate(colours):									# a stack of pipes
			y = top + i * gap
			d.rounded_rectangle([34, y, w - 44, y + gap - 1], radius=6, fill=c + (255,))
			d.line([(40, y + 3), (w - 50, y + 3)], fill=shade(c, 1.25) + (255,), width=2)
			d.ellipse([28, y, 40, y + gap - 1], fill=shade(c, 0.6) + (255,))
		for x in (90, 210, 330):											# tie-down straps
			d.line([(x, 6), (x, h - 6)], fill=(230, 160, 30, 255), width=4)
	wheels(d, [40, 66], w, h)
	lamps(d, w, h)


def trailer_tanker(img, liv):
	name, base, accent, textc, _ = liv
	w, h = img.size
	d = ImageDraw.Draw(img)
	silver = (196, 200, 208)
	# the chassis peeks out at both ends, the tank is a long capsule
	d.rounded_rectangle([0, 14, w - 1, h - 15], radius=6, fill=(60, 60, 66, 255), outline=OUTLINE, width=2)
	d.rounded_rectangle([10, 0, w - 8, h - 1], radius=48, fill=silver + (255,), outline=OUTLINE, width=3)
	d.rounded_rectangle([22, 8, w - 20, 26], radius=9, fill=shade(silver, 1.15) + (255,))		# top highlight
	d.rounded_rectangle([22, h - 30, w - 20, h - 12], radius=9, fill=shade(silver, 0.86) + (255,))
	d.line([(24, 38), (w - 22, 38)], fill=shade(silver, 0.75) + (255,), width=2)				# walkway
	for x in (60, 140, 220, 300):																# manholes on the walkway
		d.ellipse([x, 26, x + 24, 50], fill=shade(silver, 0.7) + (255,), outline=OUTLINE, width=2)
		d.ellipse([x + 7, 33, x + 17, 43], fill=shade(silver, 0.9) + (255,))
	d.rectangle([w - 60, 30, w - 40, h - 30], fill=accent + (255,))
	text_along(img, name, (40, 58, w - 70, h - 18), textc, 26)
	wheels(d, [42, 68], w, h)
	lamps(d, w, h)


def trailer_container(img, liv):
	name, base, accent, textc, _ = liv
	w, h = img.size
	d = ImageDraw.Draw(img)
	# chassis rails, then a 40 ft box on it that does not reach the ends
	d.rounded_rectangle([0, 18, w - 1, h - 19], radius=4, fill=(52, 52, 58, 255), outline=OUTLINE, width=2)
	d.rectangle([w - 24, 8, w - 6, h - 9], fill=(70, 70, 76, 255))
	x0, x1 = 30, w - 30
	d.rectangle([x0, 2, x1, h - 3], fill=base + (255,), outline=OUTLINE, width=3)
	for x in range(x0 + 10, x1 - 8, 8):														# corrugation
		d.line([(x, 6), (x, h - 7)], fill=shade(base, 0.8) + (255,), width=2)
	for cx in (x0 + 2, x1 - 10):																# corner castings
		for cy in (4, h - 13):
			d.rectangle([cx, cy, cx + 8, cy + 8], fill=(40, 40, 44, 255))
	d.rectangle([x0 + 14, h / 2 - 22, x1 - 14, h / 2 + 22], fill=shade(base, 1.06) + (255,))
	text_along(img, name, (x0 + 18, h / 2 - 20, x1 - 18, h / 2 + 20), textc, 38)
	wheels(d, [40, 66], w, h)
	lamps(d, w, h)


def make_trailer(kind, liv):
	img = Image.new('RGBA', TRAILER, (0, 0, 0, 0))
	if kind == 'box':
		trailer_box(img, liv)
	elif kind == 'reefer':
		trailer_reefer(img, liv)
	elif kind == 'curtain':
		trailer_curtain(img, liv)
	elif kind == 'flatbed_tarp':
		trailer_flatbed(img, liv, 'tarp')
	elif kind == 'flatbed_pipes':
		trailer_flatbed(img, liv, 'pipes')
	elif kind == 'tanker':
		trailer_tanker(img, liv)
	elif kind == 'container':
		trailer_container(img, liv)
	return img


# --- the cab: European cab-over -------------------------------------------------------

def make_cab(colour, with_front_wheels=True, accent=None):
	w, h = CAB
	img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	# wheels first, under the body, inset so they stay inside the box
	xs = [8, w - 30] if with_front_wheels else [8]
	for x in xs:
		for y in (2, h - 12):
			d.rounded_rectangle([x, y, x + 20, y + 10], radius=3, fill=(24, 24, 28, 255))
	# body, slightly narrower than the box so the wheels show at the sides
	body(img, [2, 6, w - 3, h - 7], colour, radius=9)
	# roof panel lighter, air deflector darker at the rear, windscreen at the front
	d.rounded_rectangle([26, 14, w - 30, h - 15], radius=6, fill=shade(colour, 1.12) + (255,))
	d.polygon([(6, 12), (24, 9), (24, h - 10), (6, h - 13)], fill=shade(colour, 0.7) + (255,))
	d.rounded_rectangle([w - 26, 10, w - 8, h - 11], radius=3, fill=(28, 34, 52, 255))
	d.line([(w - 22, 14), (w - 12, 14)], fill=(120, 150, 200, 255), width=2)					# glass glint
	d.rectangle([w - 30, 10, w - 27, h - 11], fill=shade(colour, 0.65) + (255,))				# sun visor
	if accent:
		d.rectangle([30, h / 2 - 5, w - 34, h / 2 + 5], fill=accent + (255,))
	for x in (w - 24, w - 18, w - 12):															# roof marker lights
		d.ellipse([x, 6, x + 4, 10], fill=(255, 170, 50, 255))
		d.ellipse([x, h - 11, x + 4, h - 7], fill=(255, 170, 50, 255))
	for y in (10, h - 15):																		# headlights
		d.rectangle([w - 7, y, w - 3, y + 5], fill=(255, 245, 200, 255))
	for y in (4, h - 9):																		# mirrors
		d.rectangle([w - 32, y, w - 24, y + 5], fill=(60, 60, 66, 255))
	d.ellipse([12, 10, 20, 18], fill=(40, 40, 44, 255))											# exhaust stack
	return img


# --- preview ------------------------------------------------------------------------

def preview(trailers, cabs):
	cols = 2
	cell_w, cell_h = TRAILER[0] + CAB[0] + 40, TRAILER[1] + 24
	rows = (len(trailers) + cols - 1) // cols
	sheet = Image.new('RGB', (cols * cell_w + 20, rows * cell_h + 420), (38, 40, 48))
	for i, (name, t, c) in enumerate(trailers):
		x = 10 + (i % cols) * cell_w
		y = 10 + (i // cols) * cell_h
		sheet.paste(t, (x, y), t)
		sheet.paste(c, (x + TRAILER[0] + 12, y + (TRAILER[1] - CAB[1]) // 2), c)
	# three rigs at the size the iPad shows them (about 2.6 px per unit), with the game's shadow
	y0 = rows * cell_h + 30
	scale = 2.6 / PX
	for j, (name, t, c) in enumerate(trailers[:5]):
		ts = t.resize((int(t.width * scale), int(t.height * scale)), Image.LANCZOS)
		cs = c.resize((int(c.width * scale), int(c.height * scale)), Image.LANCZOS)
		x = 20 + j * (ts.width + cs.width + 40)
		for im, dx in ((ts, 0), (cs, ts.width + 2)):
			sh = Image.new('RGBA', im.size, (0, 0, 0, 140))
			sh.putalpha(im.split()[3].point(lambda v: v * 140 // 255))
			sheet.paste(sh, (x + dx + 8, y0 + 8), sh)
			sheet.paste(im, (x + dx, y0), im)
	# and the same rigs rotated, to check they read at an angle
	y1 = y0 + 90
	for j, (name, t, c) in enumerate(trailers[5:10]):
		rig = Image.new('RGBA', (TRAILER[0] + CAB[0] + 4, TRAILER[1]), (0, 0, 0, 0))
		rig.paste(t, (0, 0), t)
		rig.paste(c, (TRAILER[0] + 4, (TRAILER[1] - CAB[1]) // 2), c)
		rig = rig.resize((int(rig.width * scale), int(rig.height * scale)), Image.LANCZOS).rotate(-28 - j * 25, expand=True, resample=Image.BICUBIC)
		x = 20 + j * 230
		sheet.paste(rig, (x, y1), rig)
	return sheet


if __name__ == '__main__':
	os.makedirs(OUT, exist_ok=True)
	trailers, cabs = [], []
	for li, liv in enumerate(LIVERIES):
		cab = make_cab(liv[4], accent=liv[1] if liv[4] != liv[1] else liv[2])
		cab.save(os.path.join(OUT, 'cab_L%d.png' % li), optimize=True)
		for vi, kind in enumerate(TYPES_PER_LIVERY[li]):
			t = make_trailer(kind, liv)
			t.save(os.path.join(OUT, 'trailer_L%d_%d.png' % (li, vi + 1)), optimize=True)
			trailers.append((liv[0], t, cab))
	player_liv = ('SKILLED TRUCKER', (245, 247, 250), (222, 40, 45), (222, 40, 45), (222, 40, 45))
	pt = make_trailer('box', player_liv)
	pt.save(os.path.join(OUT, 'trailer_player.png'), optimize=True)
	pc = make_cab((222, 40, 45), with_front_wheels=False, accent=(245, 247, 250))
	pc.save(os.path.join(OUT, 'cab_player.png'), optimize=True)
	trailers.insert(0, ('PLAYER', pt, pc))
	total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
	print('%d files, %d KB' % (len(os.listdir(OUT)), total // 1024))
	preview(trailers, cabs).save(os.path.join(HERE, 'cache', 'truck_preview.png'))
	print('preview -> tools/cache/truck_preview.png')
