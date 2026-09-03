#!/usr/bin/env python3
"""Generates the WAV files for SampledSoundEngine into ../App/Sounds. Stdlib only.

    python3 make_sounds.py

Loops are seamless by construction: every partial completes a whole number of cycles
inside the file, and the noise beds are crossfaded across their own ends.
"""
import math, os, random, struct, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'App', 'Sounds')
random.seed(7)


def write(name, samples):
	peak = max(1e-9, max(abs(s) for s in samples))
	scale = 0.92 / peak if peak > 0.92 else 1.0
	data = struct.pack('<%dh' % len(samples), *[int(max(-1, min(1, s * scale)) * 32767) for s in samples])
	path = os.path.join(OUT, name + '.wav')
	with wave.open(path, 'wb') as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(RATE)
		w.writeframes(data)
	print('%-18s %5.2fs %6d bytes' % (name, len(samples) / RATE, os.path.getsize(path)))


def seconds(n):
	return int(n * RATE)


def crossfade_loop(samples, fade):
	"""Blend the tail into the head so a noise bed loops without a click."""
	n = len(samples)
	out = samples[:]
	for i in range(fade):
		t = i / fade
		out[i] = samples[i] * t + samples[n - fade + i] * (1 - t)
	return out[:n - fade]


def engine_loop():
	# Fundamental 40 Hz: 40 whole cycles in one second, so every harmonic loops cleanly.
	length, f0 = seconds(1.0), 40.0
	phases = [random.random() * 2 * math.pi for _ in range(40)]
	out = []
	for i in range(length):
		t = i / RATE
		s = 0.0
		for n in range(1, 40):
			s += math.sin(2 * math.pi * f0 * n * t + phases[n]) / (n ** 1.15)
		rattle = 1 + 0.25 * math.sin(2 * math.pi * f0 * 2 * t)
		out.append(math.tanh(s * 0.7 * rattle))
	return out


def ambient_loop():
	# Brown noise from a leaky integrator, so it wanders without sitting on a rail, then
	# high-passed to take the DC out: distant highway and idling diesels.
	length, fade = seconds(4.0) + seconds(0.25), seconds(0.25)
	out, brown, lp, hp_prev_in, hp_prev_out = [], 0.0, 0.0, 0.0, 0.0
	for _ in range(length):
		brown = brown * 0.998 + (random.random() * 2 - 1) * 0.02
		lp += (brown - lp) * 0.05
		hp_prev_out = 0.995 * (hp_prev_out + lp - hp_prev_in)
		hp_prev_in = lp
		out.append(hp_prev_out)
	peak = max(abs(s) for s in out)
	return crossfade_loop([s / peak for s in out], fade)


def beeper_loop():
	# 0.7 s period, tone for 45% of it, with a 4 ms ramp so it does not click.
	length, on, ramp = seconds(0.7), seconds(0.7 * 0.45), seconds(0.004)
	out = []
	for i in range(length):
		env = 0.0
		if i < on:
			env = min(1.0, i / ramp, (on - i) / ramp)
		out.append(math.sin(2 * math.pi * 1000 * i / RATE) * env * 0.5)
	return out


def crash():
	length = seconds(0.7)
	out = []
	for i in range(length):
		t = i / RATE
		env = math.exp(-t / 0.18)
		thump = math.sin(2 * math.pi * 55 * t) * math.exp(-t / 0.12)
		out.append((random.random() * 2 - 1) * env * 0.9 + thump * 0.8)
	return out


def jam():
	length = seconds(0.25)
	out = []
	for i in range(length):
		t = i / RATE
		env = math.exp(-t / 0.07)
		click = (random.random() * 2 - 1) * math.exp(-t / 0.01) * 0.4
		out.append(math.sin(2 * math.pi * 85 * t) * env * 0.8 + click)
	return out


def horn():
	length = seconds(1.0)
	out = []
	for i in range(length):
		t = i / RATE
		env = min(1.0, t / 0.05, (1.0 - t) / 0.25)
		s = 0.0
		for f in (233.0, 311.0):
			s += math.sin(2 * math.pi * f * t) + 0.4 * math.sin(2 * math.pi * 2 * f * t) \
				+ 0.2 * math.sin(2 * math.pi * 3 * f * t)
		out.append(s * env * 0.3)
	return out


if __name__ == '__main__':
	os.makedirs(OUT, exist_ok=True)
	write('engine_loop', engine_loop())
	write('ambient_loop', ambient_loop())
	write('beeper_loop', beeper_loop())
	write('crash', crash())
	write('jam', jam())
	write('horn', horn())
