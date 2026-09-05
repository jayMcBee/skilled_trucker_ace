#!/usr/bin/env python3
"""Renders every sound into ../CrazySkilledTrucker/Sounds, and spectrograms into cache/.

    ../../..scratch/venv/bin/python make_sounds.py      # needs numpy and Pillow; ffmpeg for the horn

Engine loops come from a diesel model: a train of firing pulses at RPM / 60 * cylinders / 2,
each pulse a short decaying burst of tone and noise, with per-cylinder imbalance and
timing jitter, through body resonances and an exhaust low-pass, with a rattle of noise
that follows the pulses and a turbo whine under load. Three loops at three loads are
crossfaded in the game. Every loop holds a whole number of firings, and the filters run
over three copies and keep the middle one, so the seams are silent.

The horn is a CC0 recording from BigSoundBank (#2721), fetched into cache/ and converted
with ffmpeg; without ffmpeg or a network the synthesised horn is written instead.
"""
import math, os, subprocess, urllib.request
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'CrazySkilledTrucker', 'Sounds')
CACHE = os.path.join(HERE, 'cache')
RATE = 22050
HORN_URL = 'https://www.bigsoundbank.com/UPLOAD/mp3/2721.mp3'
rng = np.random.default_rng(7)


# --- helpers -------------------------------------------------------------------------

def write(name, samples, peak=0.9):
	x = np.asarray(samples, dtype=np.float64)
	top = np.max(np.abs(x)) or 1.0
	x = np.tanh(x / top * 1.15) / math.tanh(1.15) * peak			# soft top, then normalise
	data = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
	path = os.path.join(OUT, name + '.wav')
	with open(path, 'wb') as f:
		n = len(data)
		f.write(b'RIFF' + (36 + n).to_bytes(4, 'little') + b'WAVEfmt ' + (16).to_bytes(4, 'little')
				+ (1).to_bytes(2, 'little') + (1).to_bytes(2, 'little') + RATE.to_bytes(4, 'little')
				+ (RATE * 2).to_bytes(4, 'little') + (2).to_bytes(2, 'little') + (16).to_bytes(2, 'little')
				+ b'data' + n.to_bytes(4, 'little') + data)
	print('%-16s %5.2fs %7d bytes' % (name, len(x) / RATE, os.path.getsize(path)))
	return x


def biquad(x, b, a):
	"""Direct form I, in plain Python: a few hundred thousand samples is fine offline."""
	b0, b1, b2 = b
	a1, a2 = a[1], a[2]
	y = np.empty_like(x)
	x1 = x2 = y1 = y2 = 0.0
	for i, x0 in enumerate(x):
		y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		y[i] = y0
		x2, x1, y2, y1 = x1, x0, y1, y0
	return y


def rbj(kind, f, q):
	w = 2 * math.pi * f / RATE
	alpha = math.sin(w) / (2 * q)
	c = math.cos(w)
	if kind == 'lowpass':
		b = ((1 - c) / 2, 1 - c, (1 - c) / 2)
	elif kind == 'highpass':
		b = ((1 + c) / 2, -(1 + c), (1 + c) / 2)
	else:															# bandpass, constant skirt gain
		b = (q * alpha, 0, -q * alpha)
	a = (1 + alpha, -2 * c, 1 - alpha)
	return tuple(v / a[0] for v in b), tuple(v / a[0] for v in a)


def bandpass(x, f, q):
	return biquad(x, *rbj('bandpass', f, q))


def lowpass(x, f, q=0.7):
	return biquad(x, *rbj('lowpass', f, q))


def highpass(x, f, q=0.7):
	return biquad(x, *rbj('highpass', f, q))


def middle(x3):
	n = len(x3) // 3
	return x3[n:2 * n]


def periodic_noise(n, falloff, seed):
	"""Noise whose spectrum falls as 1/f^falloff, periodic in n samples, so it loops."""
	r = np.random.default_rng(seed)
	f = np.abs(np.fft.rfftfreq(n))
	f[0] = 1
	spec = (r.standard_normal(len(f)) + 1j * r.standard_normal(len(f))) / f ** falloff
	spec[0] = 0
	y = np.fft.irfft(spec, n)
	return y / np.max(np.abs(y))


def crossfade_loop(x, fade):
	out = x.copy()
	t = np.linspace(0, 1, fade)
	out[:fade] = x[:fade] * t + x[-fade:] * (1 - t)
	return out[:-fade]


# --- the diesel -----------------------------------------------------------------------

def diesel(rpm, load, seconds=2.0, cylinders=6, seed=1):
	r = np.random.default_rng(seed)
	fire = rpm / 60 * cylinders / 2
	firings = int(round(seconds * fire))
	n = int(round(firings / fire * RATE))
	period = n / firings
	exc = np.zeros(n)
	cylinder_gain = 1 + 0.14 * r.standard_normal(cylinders)
	cylinder_lag = 0.025 * r.standard_normal(cylinders)
	pulse_len = int(0.014 * RATE)
	tp = np.arange(pulse_len) / RATE
	tau = 0.0045 - 0.002 * load
	body = 130 + 80 * load
	for k in range(firings):
		c = k % cylinders
		start = int(round(k * period + (cylinder_lag[c] + 0.008 * r.standard_normal()) * period))
		amp = cylinder_gain[c] * (0.8 + 0.4 * r.random())
		pulse = np.exp(-tp / tau) * (0.8 * np.sin(2 * np.pi * body * tp) + 0.6 * r.standard_normal(pulse_len))
		idx = (start + np.arange(pulse_len)) % n						# wraps: the loop is periodic
		exc[idx] += amp * pulse
	x3 = np.tile(exc, 3)
	tone = (bandpass(x3, 85 + 45 * load, 2.5) * 1.0
			+ bandpass(x3, 190 + 40 * load, 4.0) * 0.8
			+ bandpass(x3, 420 + 380 * load, 5.0) * (0.25 + 0.6 * load)
			+ x3 * 0.35)
	tone = lowpass(tone, 550 + 2600 * load)
	env = lowpass(np.abs(x3), 120)
	env = env / (np.max(env) or 1)
	rattle = highpass(r.standard_normal(len(x3)), 2200) * env * (0.10 + 0.14 * load)
	t3 = np.arange(len(x3)) / RATE
	whine_f = 1500 + 2300 * load
	whine = np.sin(2 * np.pi * whine_f * t3 + 0.6 * np.sin(2 * np.pi * 3.1 * t3)) * (0.06 * load ** 2)
	hum = np.sin(2 * np.pi * fire * t3) * 0.25 * (1 - load)			# the soft idle thud under it all
	return middle(tone + rattle + whine + hum)


def coast(seconds=2.0):
	n = int(seconds * RATE)
	road = lowpass(np.tile(periodic_noise(n, 1.0, 21), 3), 900)
	wind = lowpass(np.tile(periodic_noise(n, 0.5, 22), 3), 2500) * 0.35
	hum = np.sin(2 * np.pi * 95 * np.arange(3 * n) / RATE) * 0.12
	return middle(road + wind + hum)


# --- one-shots --------------------------------------------------------------------------

def envelope(n, attack, decay, hold=0.0):
	t = np.arange(n) / RATE
	a = np.clip(t / max(attack, 1e-4), 0, 1)
	d = np.exp(-np.clip(t - attack - hold, 0, None) / decay)
	return a * d


def ring(n, partials, decay, level):
	t = np.arange(n) / RATE
	out = np.zeros(n)
	for i, f in enumerate(partials):
		out += np.sin(2 * np.pi * f * t) * np.exp(-t / (decay * (1 - 0.15 * i))) * level / (i + 1)
	return out


def crash():
	n = int(1.3 * RATE)
	transient = rng.standard_normal(n) * envelope(n, 0.001, 0.012) * 1.6
	body = lowpass(rng.standard_normal(n), 300) * envelope(n, 0.002, 0.09) * 2.5
	metal = ring(n, [183, 311, 468, 742], 0.45, 0.9)
	scrape = np.zeros(n)
	t = np.arange(n) / RATE
	for i in range(0, n, 512):
		f = 700 + 2300 * min(1, i / (0.5 * RATE))
		seg = bandpass(rng.standard_normal(min(512, n - i) + 64), f, 6)[:min(512, n - i)]
		scrape[i:i + len(seg)] = seg
	scrape *= envelope(n, 0.01, 0.25, hold=0.15) * 0.7
	debris = np.zeros(n)
	for _ in range(14):
		at = int((0.15 + 0.85 * rng.random() ** 2) * RATE)
		m = int(0.004 * RATE)
		if at + m < n:
			debris[at:at + m] += bandpass(rng.standard_normal(m + 64), 1000 + 4000 * rng.random(), 5)[:m] * (0.6 * (1 - at / n))
	return transient + body + metal + scrape + debris


def jam():
	n = int(0.35 * RATE)
	transient = rng.standard_normal(n) * envelope(n, 0.001, 0.008) * 1.2
	thud = lowpass(rng.standard_normal(n), 200) * envelope(n, 0.002, 0.05) * 2.0
	metal = ring(n, [122, 197, 305], 0.14, 0.8)
	return transient + thud + metal


def brake_hiss(seed):
	"""One puff. Three of these differ in length, colour and level, so a stop never
	sounds like the last one."""
	r = np.random.default_rng(seed)
	decay = 0.16 + 0.12 * r.random()
	n = int((0.12 + decay * 3) * RATE)
	noise = (bandpass(r.standard_normal(n), 2200 + 900 * r.random(), 0.9)
			 + bandpass(r.standard_normal(n), 1200 + 500 * r.random(), 1.2) * 0.5)
	return noise * envelope(n, 0.012 + 0.01 * r.random(), decay, hold=0.02 + 0.04 * r.random())


def beeper_loop():
	n = int(0.7 * RATE)
	on = int(0.7 * 0.45 * RATE)
	t = np.arange(n) / RATE
	tone = np.sin(2 * np.pi * 1220 * t) + 0.25 * np.sin(2 * np.pi * 2440 * t)
	ramp = int(0.005 * RATE)
	env = np.zeros(n)
	env[:on] = np.minimum(1, np.minimum(np.arange(on) / ramp, (on - np.arange(on)) / ramp))
	return tone * env * 0.5


def horn_synth():
	n = int(1.2 * RATE)
	t = np.arange(n) / RATE
	env = np.minimum(1, np.minimum(t / 0.06, (1.2 - t) / 0.3))
	out = np.zeros(n)
	for f in (233.0, 311.0, 349.0):
		out += (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * 2 * f * t) + 0.3 * np.sin(2 * np.pi * 3 * f * t)
				+ 0.15 * np.sin(2 * np.pi * 4 * f * t))
	return lowpass(out * env, 2500)


def horn_recording():
	"""BigSoundBank #2721, CC0. Returns samples, or None when it cannot be fetched or decoded."""
	os.makedirs(CACHE, exist_ok=True)
	mp3 = os.path.join(CACHE, 'horn_2721.mp3')
	raw = os.path.join(CACHE, 'horn_2721.raw')
	try:
		if not os.path.exists(mp3):
			urllib.request.urlretrieve(HORN_URL, mp3)
		subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-ac', '1', '-ar', str(RATE),
						'-f', 's16le', raw], check=True)
	except Exception as e:
		print('horn recording unavailable (%s), writing the synthesised one' % e)
		return None
	x = np.frombuffer(open(raw, 'rb').read(), dtype='<i2').astype(np.float64) / 32768
	loud = np.abs(x) > 0.004
	start, end = np.argmax(loud), len(x) - np.argmax(loud[::-1])
	x = x[max(0, start - int(0.02 * RATE)):min(len(x), end + int(0.1 * RATE))]
	fade = int(0.15 * RATE)
	x[-fade:] *= np.linspace(1, 0, fade)
	return x


def ambient(seconds=8.0):
	n = int(seconds * RATE)
	highway = lowpass(np.tile(periodic_noise(n, 1.1, 31), 3), 700)
	distant_idle = np.tile(diesel(620, 0.1, seconds=2.0, seed=41), int(math.ceil(3 * n / (2 * RATE))))[:3 * n]
	distant_idle = lowpass(distant_idle, 260) * 0.35
	second_idle = np.tile(diesel(700, 0.15, seconds=2.0, seed=42), int(math.ceil(3 * n / (2 * RATE))))[:3 * n]
	second_idle = lowpass(second_idle, 220) * 0.25
	return crossfade_loop(middle(highway + distant_idle + second_idle), int(0.5 * RATE))


# --- spectrograms, to look at what cannot be heard here -------------------------------

def spectrogram(x, name, top=4000):
	win = 1024
	hop = 256
	frames = max(1, (len(x) - win) // hop)
	spec = np.zeros((win // 2 + 1, frames))
	w = np.hanning(win)
	for i in range(frames):
		seg = x[i * hop:i * hop + win] * w
		spec[:, i] = np.abs(np.fft.rfft(seg))
	spec = 20 * np.log10(spec + 1e-6)
	spec = np.clip((spec - spec.max() + 70) / 70, 0, 1)
	rows = int(top / (RATE / 2) * spec.shape[0])
	img = Image.fromarray((spec[:rows][::-1] * 255).astype(np.uint8), 'L').resize((min(900, frames * 2), 300))
	img.save(os.path.join(CACHE, 'spec_%s.png' % name))


if __name__ == '__main__':
	os.makedirs(OUT, exist_ok=True)
	os.makedirs(CACHE, exist_ok=True)
	loops = {
		'engine_idle': diesel(650, 0.15, seed=1),
		'engine_low': diesel(1000, 0.5, seed=2),
		'engine_high': diesel(1500, 1.0, seed=3),
		'engine_coast': coast(),
	}
	for name, x in loops.items():
		spectrogram(write(name, x, peak=0.8), name)
	spectrogram(write('ambient_loop', ambient(), peak=0.6), 'ambient_loop')
	write('beeper_loop', beeper_loop(), peak=0.6)
	spectrogram(write('crash', crash()), 'crash')
	write('jam', jam())
	for i in range(3):
		x = write('brake_hiss%d' % (i + 1), brake_hiss(50 + i), peak=0.45 + 0.1 * i)
		if i == 0:
			spectrogram(x, 'brake_hiss')
	horn = horn_recording()
	write('horn', horn if horn is not None else horn_synth(), peak=0.85)
	for stale in ('engine_loop.wav', 'brake_hiss.wav'):
		path = os.path.join(OUT, stale)
		if os.path.exists(path):
			os.remove(path)
	total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
	print('total %d KB, spectrograms in tools/cache/spec_*.png' % (total // 1024))
