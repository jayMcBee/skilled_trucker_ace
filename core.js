// core.js — rig kinematics, collision, level data.
// Shared by index.html (plain <script>, no build step) and `node core.js`, which runs the self-check.
//
// ONE convention everywhere: local +x is forward. `angle` is the direction the nose points.
//
// Everything is specified in METRES and scaled to pixels by the active preset. Switching preset
// therefore rescales the rig and the lot together, so what you feel is the handling change and
// not an accidental change in how much room you were given.

// --- specification, in metres ----------------------------------------------

var SPEC = {
	trailerLen: 16.15,      // 53 ft box
	trailerWid: 4.38,       // stylised ~1.7x wide: readable at this zoom, and consistent lot-wide
	cabLen: 4.58,
	cabWid: 3.96,
	kingpinToAxle: 12.29,   // the trailer's effective wheelbase, and the D in every formula below
	rigLen: 20.83,          // a parked tractor+trailer drawn as one box
	rigWid: 6.04,

	// Two independent speeds, not a speed and a factor. The fold develops per METRE travelled,
	// not per second, so reverse speed buys nothing but reaction time -- and forward speed costs
	// nothing, because the fold converges going forward. They are unrelated numbers.
	fwdSpeed: 5.60,         // m/s = 20.2 km/h
	revSpeed: 2.20,         // m/s = 7.9 km/h
	accel: 7.00,
	friction: 7.00,
	maxSteer: 0.42,         // 24 deg
	steerRate: 0.7,         // 0.6 s centre to lock

	lot: {
		parkHeading: 0.673,
		rowStart: { x: 26.04, y: 50.00 },
		rowSpacing: 6.458,
		rowCount: 7,
		targetSlot: 3,
		extra: [{ x: 26.04, y: 62.29, angle: 0 }, { x: 66.67, y: 62.29, angle: 0 }],
		start: { x: 66.67, y: 52.08, angle: 2.244 }
	}
};

// pxPerM is zoom. wheelbase is handling: W/D is a ratio of two metre values, so it is
// scale-invariant and the two knobs never interfere.
var PRESETS = [
	{ key: '1', name: 'Current',        pxPerM: 9.60, wheelbase: 3.54, baseline: true },   // the 'before', kept for comparison
	{ key: '2', name: 'A sleeper WB',   pxPerM: 9.60, wheelbase: 6.10 },
	{ key: '3', name: 'B zoomed out',   pxPerM: 6.19, wheelbase: 6.10 },
	{ key: '4', name: 'C docile',       pxPerM: 6.19, wheelbase: 8.59 },
	{ key: '5', name: 'D very docile',  pxPerM: 6.19, wheelbase: 12.29 }
];

var CANVAS = { w: 850, h: 650 };

// Tuning dials, driven from the UI. Separate, because they trade against completely different
// things: forward speed against nothing at all, reverse speed against the fold clock.
var FWD = 1, REV = 1;
function setFwd(v) { FWD = clamp(v, 0.3, 2.5); return FWD; }
function setRev(v) { REV = clamp(v, 0.3, 3.0); return REV; }
var PRESET, SCALE, TRUCK, LEVEL;

function usePreset(i) {
	PRESET = PRESETS[i];
	SCALE = PRESET.pxPerM;
	var m = function (v) { return v * SCALE; };

	TRUCK = { trailerLen: m(SPEC.trailerLen), trailerWid: m(SPEC.trailerWid),
		cabLen: m(SPEC.cabLen), cabWid: m(SPEC.cabWid),
		rigLen: m(SPEC.rigLen), rigWid: m(SPEC.rigWid) };

	var L = SPEC.lot, i2;
	LEVEL = { parkHeading: L.parkHeading, rowSpacing: m(L.rowSpacing),
		rowCount: L.rowCount, targetSlot: L.targetSlot,
		rowStart: { x: m(L.rowStart.x), y: m(L.rowStart.y) },
		extra: [], start: { x: m(L.start.x), y: m(L.start.y), angle: L.start.angle } };
	for (i2 = 0; i2 < L.extra.length; i2++)
		LEVEL.extra.push({ x: m(L.extra[i2].x), y: m(L.extra[i2].y), angle: L.extra[i2].angle });

	centreLot();
	return PRESET;
}

// Zooming out leaves the lot hugging one corner. Shift it so every preset is framed the same.
function centreLot() {
	var pts = [LEVEL.start], i, j, c;
	for (i = 0; i < LEVEL.rowCount; i++) pts.push(slotCentre(i));
	for (i = 0; i < LEVEL.extra.length; i++) pts.push(LEVEL.extra[i]);
	var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
	for (i = 0; i < pts.length; i++) {
		c = getBoxCorners(pts[i].x, pts[i].y, TRUCK.rigLen, TRUCK.rigWid,
			pts[i].angle === undefined ? LEVEL.parkHeading : pts[i].angle);
		for (j = 0; j < 4; j++) {
			if (c[j].x < minX) minX = c[j].x;
			if (c[j].x > maxX) maxX = c[j].x;
			if (c[j].y < minY) minY = c[j].y;
			if (c[j].y > maxY) maxY = c[j].y;
		}
	}
	var dx = (CANVAS.w - (maxX - minX)) / 2 - minX, dy = (CANVAS.h - (maxY - minY)) / 2 - minY;
	LEVEL.rowStart.x += dx; LEVEL.rowStart.y += dy;
	LEVEL.start.x += dx; LEVEL.start.y += dy;
	for (i = 0; i < LEVEL.extra.length; i++) { LEVEL.extra[i].x += dx; LEVEL.extra[i].y += dy; }
}

function slotCentre(i) {
	var a = LEVEL.parkHeading - Math.PI / 2;
	return { x: LEVEL.rowStart.x + Math.cos(a) * LEVEL.rowSpacing * i,
		y: LEVEL.rowStart.y + Math.sin(a) * LEVEL.rowSpacing * i };
}

// Seconds of full-lock reversing before the fold reaches the stop. This is what reverse speed
// buys, and the only thing it buys, so the UI shows it next to the dial.
function foldClock() {
	var r = makeRig(0, 0, 0), dt = 1 / 60;
	r.trailer.angle = 0.02;
	for (var i = 0; i < 120 / dt; i++) {
		r.steer = r.maxSteer;
		stepRig(r, -1, 0, dt);
		if (Math.abs(normAngle(r.angle - r.trailer.angle)) > 1.44) return i * dt;
	}
	return null;
}

// Headline numbers for the on-screen readout: what each preset actually changes.
function presetStats() {
	var R = PRESET.wheelbase / Math.tan(SPEC.maxSteer);              // metres
	var s = (SPEC.kingpinToAxle / PRESET.wheelbase) * Math.tan(SPEC.maxSteer);
	return {
		name: PRESET.name,
		fwd: FWD, rev: REV,
		fwdKmh: SPEC.fwdSpeed * FWD * 3.6,
		revKmh: SPEC.revSpeed * REV * 3.6,
		foldClock: foldClock(),
		ratio: PRESET.wheelbase / SPEC.kingpinToAxle,
		turnRadiusPx: R * SCALE,
		turnPerRig: R / SPEC.rigLen,
		rigLenPx: TRUCK.rigLen,
		foldsForward: s > 1,
		settlesAt: s <= 1 ? Math.asin(s) * 57.3 : null
	};
}

// --- geometry --------------------------------------------------------------

function normAngle(a) { return Math.atan2(Math.sin(a), Math.cos(a)); }
function towardZero(v, step) { return v > 0 ? Math.max(0, v - step) : Math.min(0, v + step); }
function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

function getBoxCorners(x, y, len, wid, angle) {
	var cos = Math.cos(angle), sin = Math.sin(angle);
	var hl = len / 2, hw = wid / 2;
	return [
		{ x: x - hl * cos + hw * sin, y: y - hl * sin - hw * cos },
		{ x: x + hl * cos + hw * sin, y: y + hl * sin - hw * cos },
		{ x: x + hl * cos - hw * sin, y: y + hl * sin + hw * cos },
		{ x: x - hl * cos - hw * sin, y: y - hl * sin + hw * cos }
	];
}

function aabbCorners(x, y, w, h) {
	return [{ x: x, y: y }, { x: x + w, y: y }, { x: x + w, y: y + h }, { x: x, y: y + h }];
}

// Separating axis test on two convex quads.
function intersects(a, b) {
	var polys = [a, b];
	for (var p = 0; p < 2; p++) {
		var poly = polys[p];
		for (var i = 0; i < poly.length; i++) {
			var p1 = poly[i], p2 = poly[(i + 1) % poly.length];
			var nx = p2.y - p1.y, ny = p1.x - p2.x;
			var minA = Infinity, maxA = -Infinity, minB = Infinity, maxB = -Infinity, k, v;
			for (k = 0; k < a.length; k++) { v = nx * a[k].x + ny * a[k].y; if (v < minA) minA = v; if (v > maxA) maxA = v; }
			for (k = 0; k < b.length; k++) { v = nx * b[k].x + ny * b[k].y; if (v < minB) minB = v; if (v > maxB) maxB = v; }
			if (maxA < minB || maxB < minA) return false;
		}
	}
	return true;
}

// --- rig -------------------------------------------------------------------
// Tractor is a rear-axle bicycle model. The fifth wheel on a semi sits over the drive axle,
// so the hitch IS the tracked point and the trailer equation stays exact:
//     d(trailerAngle) = (v / kingpinToAxle) * sin(cabAngle - trailerAngle)
// Forward that converges, reverse it diverges, and the reverse equilibrium is UNSTABLE: there is
// no safe steering angle, only a countdown you countersteer against. Speed sets that clock.
// Whether a held wheel settles at all going forward is decided by W/D, which is what the presets vary.

var MAX_ARTICULATION = 1.45;        // ~83 degrees, then the cab is into the trailer nose
var JACKKNIFE_ENDS_RUN = false;     // ponytail: one flag, not a mode system. Extra-hard flips it.

function makeRig(x, y, angle) {
	var r = {
		x: x, y: y, angle: angle, speed: 0, steer: 0,
		wheelbase: PRESET.wheelbase * SCALE,
		maxSpeed: SPEC.fwdSpeed * SCALE * FWD,
		reverseSpeed: SPEC.revSpeed * SCALE * REV,
		accel: SPEC.accel * SCALE * Math.max(FWD, REV),
		friction: SPEC.friction * SCALE * Math.max(FWD, REV),
		maxSteer: SPEC.maxSteer,
		steerRate: SPEC.steerRate,
		trailer: { x: 0, y: 0, angle: angle, len: TRUCK.trailerLen, wid: TRUCK.trailerWid,
			kingpinToAxle: SPEC.kingpinToAxle * SCALE }
	};
	syncTrailer(r);
	return r;
}

// Kingpin sits at the trailer's front edge, so the body centre trails half a length behind.
function syncTrailer(r) {
	r.trailer.x = r.x - Math.cos(r.trailer.angle) * (r.trailer.len / 2);
	r.trailer.y = r.y - Math.sin(r.trailer.angle) * (r.trailer.len / 2);
}

function stepRig(r, drive, steerInput, dt) {
	if (!(dt > 0)) throw new Error('stepRig needs a timestep in seconds, got ' + dt);

	// The wheel is a position, not a nudge: it holds wherever you leave it, at any speed, and
	// you cancel a turn by steering back. Nothing springs to centre on its own.
	if (steerInput) {
		r.steer = clamp(r.steer + steerInput * r.steerRate * dt, -r.maxSteer, r.maxSteer);
		// Detent, so centre is findable by feel: land within half a step of zero and you get
		// exactly zero. It costs one frame passing through, it never blocks steering past it.
		if (Math.abs(r.steer) < r.steerRate * dt * 0.5) r.steer = 0;
	}

	if (drive > 0) r.speed = Math.min(r.speed + r.accel * dt, r.maxSpeed);
	else if (drive < 0) r.speed = Math.max(r.speed - r.accel * dt, -r.reverseSpeed);
	else r.speed = towardZero(r.speed, r.friction * dt);

	var travel = r.speed * dt;
	r.angle = normAngle(r.angle + (travel / r.wheelbase) * Math.tan(r.steer));
	r.x += Math.cos(r.angle) * travel;
	r.y += Math.sin(r.angle) * travel;

	var t = r.trailer;
	t.angle = normAngle(t.angle + (travel / t.kingpinToAxle) * Math.sin(r.angle - t.angle));

	// The fold always stops dead at the physical limit, so the cab can never pass through the
	// trailer. Whether reaching it also ends the run is the caller's call. The raw articulation
	// is returned unclamped so the caller can still tell the limit was hit.
	var art = normAngle(r.angle - t.angle);
	if (Math.abs(art) > MAX_ARTICULATION) t.angle = normAngle(r.angle - (art < 0 ? -MAX_ARTICULATION : MAX_ARTICULATION));
	syncTrailer(r);

	return art;
}

function rigBoxes(r) {
	var nose = TRUCK.cabLen * 0.18;
	return [
		getBoxCorners(r.x + Math.cos(r.angle) * nose, r.y + Math.sin(r.angle) * nose,
			TRUCK.cabLen, TRUCK.cabWid, r.angle),
		getBoxCorners(r.trailer.x, r.trailer.y, r.trailer.len, r.trailer.wid, r.trailer.angle)
	];
}

// --- level -----------------------------------------------------------------

function buildLot() {
	var h = LEVEL.parkHeading;
	var fwd = { x: Math.cos(h), y: Math.sin(h) };
	var parked = [], bay = null, i, back = TRUCK.rigLen / 2 - TRUCK.trailerLen / 2;

	for (i = 0; i < LEVEL.rowCount; i++) {
		var c = slotCentre(i);
		if (i === LEVEL.targetSlot) {
			// The player's trailer parks against the back of the bay, cab left sticking out.
			bay = { x: c.x, y: c.y, angle: h,
				trailerX: c.x - fwd.x * back, trailerY: c.y - fwd.y * back };
		} else {
			parked.push({ x: c.x, y: c.y, angle: h });
		}
	}
	for (i = 0; i < LEVEL.extra.length; i++) parked.push(LEVEL.extra[i]);

	var walls = [
		{ x: 0, y: 0, w: CANVAS.w, h: 15 }, { x: 0, y: CANVAS.h - 15, w: CANVAS.w, h: 15 },
		{ x: 0, y: 0, w: 15, h: CANVAS.h }, { x: CANVAS.w - 15, y: 0, w: 15, h: CANVAS.h }
	];
	return { bay: bay, parked: parked, walls: walls };
}

function lotObstacles(lot) {
	var out = [], i;
	for (i = 0; i < lot.parked.length; i++)
		out.push(getBoxCorners(lot.parked[i].x, lot.parked[i].y, TRUCK.rigLen, TRUCK.rigWid, lot.parked[i].angle));
	for (i = 0; i < lot.walls.length; i++)
		out.push(aabbCorners(lot.walls[i].x, lot.walls[i].y, lot.walls[i].w, lot.walls[i].h));
	return out;
}

usePreset(0);

// --- self-check: `node core.js` -------------------------------------------
if (typeof window === 'undefined') {
	var assert = require('assert');
	var DT = 1 / 60;
	var finite = function (o) { return Object.keys(o).every(function (k) { return typeof o[k] !== 'number' || Number.isFinite(o[k]); }); };
	var i, j;

	// SAT sanity, including the NaN case that used to hide the broken trailer.
	var A = getBoxCorners(0, 0, 100, 40, 0);
	assert.ok(intersects(A, getBoxCorners(50, 0, 100, 40, 0)), 'overlapping boxes must collide');
	assert.ok(!intersects(A, getBoxCorners(200, 0, 100, 40, 0)), 'separated boxes must not collide');
	assert.ok(!intersects(A, getBoxCorners(0, 75, 100, 40, Math.PI / 2)), 'rotated near-miss must not collide');
	assert.ok(intersects(A, getBoxCorners(0, 30, 100, 40, Math.PI / 2)), 'rotated overlap must collide');

	// Box length runs along the heading, not across it.
	assert.strictEqual(Math.max.apply(null, getBoxCorners(0, 0, 200, 40, 0).map(function (c) { return c.x; })), 100,
		'len must lie along +x');

	// stepRig without a timestep silently yields NaN, and a NaN box reports NO collision through
	// the separating-axis test. That is exactly how the original trailer bug stayed invisible.
	assert.throws(function () { stepRig(makeRig(0, 0, 0), 1, 1); }, /timestep/, 'missing dt must throw');

	// Everything below runs against EVERY preset: a preset that breaks the geometry is a bug.
	PRESETS.forEach(function (p, pi) {
		var tag = ' [preset ' + p.name + ']';
		usePreset(pi);

		// Forward is stable: an articulated rig straightens itself out.
		var r = makeRig(400, 300, 0);
		r.trailer.angle = 0.3;
		for (i = 0; i < 20 / DT; i++) stepRig(r, 1, 0, DT);
		assert.ok(Math.abs(normAngle(r.angle - r.trailer.angle)) < 0.05, 'forward must converge' + tag);

		// Reverse is unstable: the whole point of the game. Stated in SECONDS, because a frame
		// count silently becomes a different test every time the speeds or scale are retuned.
		var b = makeRig(400, 300, 0);
		b.trailer.angle = 0.05;
		var art0 = Math.abs(normAngle(b.angle - b.trailer.angle));
		for (i = 0; i < 25 / DT; i++) stepRig(b, -1, 0, DT);
		assert.ok(Math.abs(normAngle(b.angle - b.trailer.angle)) > art0 * 3, 'reverse must diverge' + tag);

		// And the fold must stay slow enough to be catchable. Under about 4 seconds there is no
		// time to react, which is what made the old 22 km/h reverse unplayable.
		var c = makeRig(400, 300, 0), foldAt = null;
		for (i = 0; i < 60 / DT; i++) {
			c.steer = c.maxSteer;
			stepRig(c, -1, 0, DT);
			if (foldAt === null && Math.abs(normAngle(c.angle - c.trailer.angle)) > 1.44) foldAt = i * DT;
		}
		// Playability bars apply to candidate presets. The baseline preset exists precisely to
		// show the bad case, so it is held to correctness only.
		if (!p.baseline)
			assert.ok(foldAt === null || foldAt > 4, 'full-lock reverse must take over 4s to fold, got ' + foldAt + tag);

		// Same, at the fastest the reverse dial goes: it must not be able to make the fold
		// uncatchable, which is the one thing it could quietly ruin.
		setRev(3.0);
		var cf = makeRig(400, 300, 0), fastFold = null;
		for (i = 0; i < 60 / DT; i++) {
			cf.steer = cf.maxSteer;
			stepRig(cf, -1, 0, DT);
			if (fastFold === null && Math.abs(normAngle(cf.angle - cf.trailer.angle)) > 1.44) fastFold = i * DT;
		}
		setRev(1);
		if (!p.baseline)
			assert.ok(fastFold === null || fastFold > 1.5, 'fold must stay catchable at max reverse dial, got ' + fastFold + tag);

		// Dry steering: the wheel holds its angle at a standstill, and a stopped rig never rotates.
		var s = makeRig(0, 0, 0);
		for (i = 0; i < 1 / DT; i++) stepRig(s, 0, 1, DT);
		var held = s.steer;
		assert.ok(held > s.maxSteer * 0.5, 'wheel must turn while stopped' + tag);
		for (i = 0; i < 1 / DT; i++) stepRig(s, 0, 0, DT);
		assert.strictEqual(s.steer, held, 'wheel must hold its angle at a standstill' + tag);
		assert.strictEqual(s.angle, 0, 'a stopped rig must not rotate' + tag);

		// Rolling, it holds too: a set wheel keeps the rig turning until you steer back.
		var mv = makeRig(0, 0, 0);
		for (i = 0; i < 1 / DT; i++) stepRig(mv, 1, 1, DT);
		var atSpeed = mv.steer;
		for (i = 0; i < 2 / DT; i++) stepRig(mv, 1, 0, DT);
		assert.strictEqual(mv.steer, atSpeed, 'wheel must hold its angle while rolling' + tag);
		// The property is that it is STILL turning after the key was released, not that it turned
		// by some amount -- a magnitude threshold is really a test of whichever preset set it.
		var before = mv.angle;
		for (i = 0; i < 0.5 / DT; i++) stepRig(mv, 1, 0, DT);
		assert.ok(Math.abs(normAngle(mv.angle - before)) > 0.02, 'a held wheel must keep the rig turning' + tag);

		// Steering back reaches exactly centre, and the detent does not trap the wheel there.
		for (i = 0; i < 5 / DT && mv.steer !== 0; i++) stepRig(mv, 1, -1, DT);
		assert.strictEqual(mv.steer, 0, 'steering back must land on exact centre' + tag);
		stepRig(mv, 1, -1, DT);
		assert.ok(mv.steer < 0, 'the centre detent must not block steering past it' + tag);

		// Frame-rate independence: the same second of driving lands in the same place at any rate.
		var slow = makeRig(0, 0, 0), fast = makeRig(0, 0, 0);
		for (i = 0; i < 60; i++) stepRig(slow, 1, 1, 1 / 60);
		for (i = 0; i < 144; i++) stepRig(fast, 1, 1, 1 / 144);
		assert.ok(Math.hypot(slow.x - fast.x, slow.y - fast.y) < 2, '60Hz and 144Hz must agree' + tag);

		// Folding hard pins at the limit rather than passing the cab through the trailer, and the
		// raw articulation still reports the overshoot so extra-hard mode can fail on it.
		var jk = makeRig(0, 0, 0), sawOvershoot = false;
		for (i = 0; i < 20 / DT; i++) {
			if (Math.abs(stepRig(jk, -1, 1, DT)) > MAX_ARTICULATION) sawOvershoot = true;
			assert.ok(Math.abs(normAngle(jk.angle - jk.trailer.angle)) <= MAX_ARTICULATION + 1e-9,
				'fold must stay inside the limit' + tag);
		}
		assert.ok(sawOvershoot, 'stepRig must report articulation past the limit' + tag);

		// No NaN anywhere.
		var n = makeRig(LEVEL.start.x, LEVEL.start.y, LEVEL.start.angle);
		for (i = 0; i < 600; i++) stepRig(n, i % 120 < 60 ? 1 : -1, Math.sin(i / 40) > 0 ? 1 : -1, DT);
		assert.ok(finite(n) && finite(n.trailer), 'rig must stay finite' + tag);

		// The lot must not park trucks inside each other, the player must not start in one, and a
		// trailer sitting correctly in the bay must not overlap anything.
		var lot = buildLot(), obs = lotObstacles(lot);
		for (i = 0; i < lot.parked.length; i++)          // walls legitimately overlap at the corners
			for (j = i + 1; j < obs.length; j++)
				assert.ok(!intersects(obs[i], obs[j]), 'lot obstacles ' + i + ' and ' + j + ' overlap' + tag);

		var pl = makeRig(LEVEL.start.x, LEVEL.start.y, LEVEL.start.angle);
		rigBoxes(pl).forEach(function (pb, k) {
			obs.forEach(function (o, mi) { assert.ok(!intersects(pb, o), 'player part ' + k + ' starts inside obstacle ' + mi + tag); });
		});

		var inBay = getBoxCorners(lot.bay.trailerX, lot.bay.trailerY, TRUCK.trailerLen, TRUCK.trailerWid, lot.bay.angle);
		obs.forEach(function (o, mi) { assert.ok(!intersects(inBay, o), 'parked-in-bay trailer overlaps obstacle ' + mi + tag); });

		// And the whole lot must actually be on screen at this zoom.
		obs.slice(0, lot.parked.length).forEach(function (o, mi) {
			o.forEach(function (pt) {
				assert.ok(pt.x > -1 && pt.x < CANVAS.w + 1 && pt.y > -1 && pt.y < CANVAS.h + 1,
					'parked truck ' + mi + ' falls outside the canvas' + tag);
			});
		});
	});

	usePreset(0);
	console.log('core.js self-check OK across ' + PRESETS.length + ' presets');
	PRESETS.forEach(function (p, pi) {
		usePreset(pi);
		var st = presetStats();
		console.log('  ' + p.key + ' ' + st.name.padEnd(15) +
			'W/D ' + st.ratio.toFixed(2) +
			'   turn ' + st.turnRadiusPx.toFixed(0).padStart(3) + 'px' +
			'   R/rig ' + st.turnPerRig.toFixed(2) +
			'   rig ' + st.rigLenPx.toFixed(0).padStart(3) + 'px' +
			'   ' + (st.foldsForward ? 'folds at lock' : 'settles at ' + st.settlesAt.toFixed(0) + ' deg').padEnd(16) +
			'   fold clock ' + (st.foldClock === null ? 'never' : st.foldClock.toFixed(1) + 's'));
	});
	usePreset(0);
}
