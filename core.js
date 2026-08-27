// core.js — rig kinematics, collision, level data.
// Shared by index.html (plain <script>, no build step) and `node core.js`, which runs the self-check.
//
// ONE convention everywhere: local +x is forward. `angle` is the direction the nose points.
// The original prototype mixed x-forward physics with y-forward drawing/collision, which put
// every hitbox 90 degrees off its heading.

var TRUCK = { cabLen: 44, cabWid: 38, trailerLen: 155, trailerWid: 42, rigLen: 200, rigWid: 58 };

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
// Tractor is a rear-axle bicycle model. The fifth wheel on a semi sits over the drive
// axle, so the hitch IS the tracked point and the trailer equation stays exact:
//     d(trailerAngle) = (v / kingpinToAxle) * sin(cabAngle - trailerAngle)
// Forward that converges (the trailer tracks). Reverse it diverges — which is the game.

var MAX_ARTICULATION = 1.45;        // ~83 degrees, then the cab is into the trailer nose
var JACKKNIFE_ENDS_RUN = false;     // ponytail: one flag, not a mode system. Extra-hard flips it.

function makeRig(x, y, angle) {
	var r = {
		x: x, y: y, angle: angle, speed: 0, steer: 0,
		// Per SECOND, not per frame. Speeds convert x60 from the old per-frame numbers,
		// accelerations x60^2 since they are distance per time SQUARED.
		//
		// Scale is fixed by the drawing: the 155px trailer is a 53ft box, so 9.6 px/m.
		// These are yard-manoeuvring numbers, not road numbers. Reversing especially: a
		// reversing trailer's equilibrium fold angle is UNSTABLE, so the fold is a countdown
		// you countersteer against, and speed sets the clock. At the old 22 km/h you had
		// barely a second. Real yard backing is idle-creep, 2-5 km/h.
		wheelbase: 34,          // 3.54 m
		maxSpeed: 45,           // 16.9 km/h forward
		reverseFactor: 0.30,    // 13.5 px/s = 5.1 km/h reversing
		accel: 60, friction: 55,
		maxSteer: 0.42,         // 24 deg. Past this the fold just gets faster, never more useful.
		steerRate: 0.7,         // 0.6 s centre to lock, in line with a heavy truck's rack
		trailer: { x: 0, y: 0, angle: angle, len: TRUCK.trailerLen, wid: TRUCK.trailerWid, kingpinToAxle: 118 }
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
	else if (drive < 0) r.speed = Math.max(r.speed - r.accel * dt, -r.maxSpeed * r.reverseFactor);
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
	return [
		getBoxCorners(r.x + Math.cos(r.angle) * 8, r.y + Math.sin(r.angle) * 8, TRUCK.cabLen, TRUCK.cabWid, r.angle),
		getBoxCorners(r.trailer.x, r.trailer.y, r.trailer.len, r.trailer.wid, r.trailer.angle)
	];
}

// --- level -----------------------------------------------------------------

var LEVEL = {
	width: 850, height: 650,
	parkHeading: 0.673,            // noses point down-right, out into the lane
	rowStart: { x: 250, y: 480 },
	rowSpacing: 62,                // 58-wide rigs: 4px of daylight between neighbours
	rowCount: 7,
	targetSlot: 3,
	extra: [{ x: 250, y: 598, angle: 0 }, { x: 640, y: 598, angle: 0 }],
	start: { x: 640, y: 500, angle: 2.244 }
};

function buildLot(L) {
	var h = L.parkHeading;
	var fwd = { x: Math.cos(h), y: Math.sin(h) };
	var across = { x: Math.cos(h - Math.PI / 2), y: Math.sin(h - Math.PI / 2) };
	var parked = [], bay = null, i;

	for (i = 0; i < L.rowCount; i++) {
		var cx = L.rowStart.x + across.x * L.rowSpacing * i;
		var cy = L.rowStart.y + across.y * L.rowSpacing * i;
		if (i === L.targetSlot) {
			// The player's trailer parks against the back of the bay, cab left sticking out.
			bay = { x: cx, y: cy, angle: h,
				trailerX: cx - fwd.x * (TRUCK.rigLen / 2 - TRUCK.trailerLen / 2),
				trailerY: cy - fwd.y * (TRUCK.rigLen / 2 - TRUCK.trailerLen / 2) };
		} else {
			parked.push({ x: cx, y: cy, angle: h });
		}
	}
	for (i = 0; i < L.extra.length; i++) parked.push(L.extra[i]);

	var walls = [
		{ x: 0, y: 0, w: L.width, h: 15 }, { x: 0, y: L.height - 15, w: L.width, h: 15 },
		{ x: 0, y: 0, w: 15, h: L.height }, { x: L.width - 15, y: 0, w: 15, h: L.height }
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

// --- self-check: `node core.js` -------------------------------------------
if (typeof window === 'undefined') {
	var assert = require('assert');
	var DT = 1 / 60;
	var finite = function (o) { return Object.keys(o).every(function (k) { return typeof o[k] !== 'number' || Number.isFinite(o[k]); }); };

	// SAT sanity, including the NaN case that used to hide the broken trailer.
	var A = getBoxCorners(0, 0, 100, 40, 0);
	assert.ok(intersects(A, getBoxCorners(50, 0, 100, 40, 0)), 'overlapping boxes must collide');
	assert.ok(!intersects(A, getBoxCorners(200, 0, 100, 40, 0)), 'separated boxes must not collide');
	assert.ok(!intersects(A, getBoxCorners(0, 75, 100, 40, Math.PI / 2)), 'rotated near-miss must not collide');
	assert.ok(intersects(A, getBoxCorners(0, 30, 100, 40, Math.PI / 2)), 'rotated overlap must collide');

	// Box length runs along the heading, not across it.
	var box = getBoxCorners(0, 0, 200, 40, 0);
	assert.ok(Math.max.apply(null, box.map(function (c) { return c.x; })) === 100, 'len must lie along +x');

	// Forward is stable: an articulated rig straightens itself out.
	var r = makeRig(400, 300, 0);
	r.trailer.angle = 0.3;
	for (var i = 0; i < 400; i++) stepRig(r, 1, 0, DT);
	assert.ok(Math.abs(normAngle(r.angle - r.trailer.angle)) < 0.05, 'forward must converge, got ' + normAngle(r.angle - r.trailer.angle));

	// Reverse is unstable: the whole point of the game. With the wheel straight the fold grows
	// at |v|/kingpinToAxle per second, so this is stated in SECONDS rather than frames -- a
	// frame count silently becomes a different test every time the speeds are retuned.
	var b = makeRig(400, 300, 0);
	b.trailer.angle = 0.05;
	var art0 = Math.abs(normAngle(b.angle - b.trailer.angle));
	for (i = 0; i < 15 / DT; i++) stepRig(b, -1, 0, DT);
	assert.ok(Math.abs(normAngle(b.angle - b.trailer.angle)) > art0 * 3, 'reverse must diverge');

	// And the fold must stay slow enough to be catchable. Under about 4 seconds at full lock
	// there is no time to react, which is what made the old 22 km/h reverse unplayable.
	var c = makeRig(400, 300, 0), foldAt = null;
	for (i = 0; i < 60 / DT; i++) {
		c.steer = c.maxSteer;
		stepRig(c, -1, 0, DT);
		if (foldAt === null && Math.abs(normAngle(c.angle - c.trailer.angle)) > 1.44) foldAt = i * DT;
	}
	assert.ok(foldAt === null || foldAt > 4, 'full-lock reverse must take over 4s to fold, got ' + foldAt);

	// Dry steering: the wheel holds its angle at a standstill, and a stopped rig never rotates.
	var s = makeRig(0, 0, 0);
	for (i = 0; i < 1 / DT; i++) stepRig(s, 0, 1, DT);       // one second of steering input
	var held = s.steer;
	assert.ok(held > s.maxSteer * 0.5, 'wheel must turn while stopped, got ' + held);
	for (i = 0; i < 1 / DT; i++) stepRig(s, 0, 0, DT);
	assert.strictEqual(s.steer, held, 'wheel must hold its angle at a standstill');
	assert.strictEqual(s.angle, 0, 'a stopped rig must not rotate');

	// Rolling, it holds too: a set wheel keeps the rig turning until you steer back.
	var m = makeRig(0, 0, 0);
	for (i = 0; i < 1 / DT; i++) stepRig(m, 1, 1, DT);
	var atSpeed = m.steer, heading = m.angle;
	for (i = 0; i < 2 / DT; i++) stepRig(m, 1, 0, DT);
	assert.strictEqual(m.steer, atSpeed, 'wheel must hold its angle while rolling');
	assert.ok(Math.abs(normAngle(m.angle - heading)) > 0.5, 'a held wheel must keep the rig turning');

	// Steering back reaches exactly centre rather than hunting around it, and passing
	// through the detent does not trap the wheel there.
	for (i = 0; i < 5 / DT && m.steer !== 0; i++) stepRig(m, 1, -1, DT);
	assert.strictEqual(m.steer, 0, 'steering back must land on exact centre');
	stepRig(m, 1, -1, DT);
	assert.ok(m.steer < 0, 'the centre detent must not block steering past it');

	// No NaN anywhere (the old build produced a NaN trailer on frame 1 and never recovered).
	var n = makeRig(LEVEL.start.x, LEVEL.start.y, LEVEL.start.angle);
	assert.ok(finite(n) && finite(n.trailer), 'rig must be finite at init');
	for (i = 0; i < 600; i++) stepRig(n, i % 120 < 60 ? 1 : -1, Math.sin(i / 40) > 0 ? 1 : -1, DT);
	assert.ok(finite(n) && finite(n.trailer), 'rig must stay finite');

	// Folding hard pins at the limit rather than passing the cab through the trailer, and the
	// raw articulation still reports the overshoot so extra-hard mode can fail on it.
	var j = makeRig(0, 0, 0), sawOvershoot = false;
	for (i = 0; i < 400; i++) {
		if (Math.abs(stepRig(j, -1, 1, DT)) > MAX_ARTICULATION) sawOvershoot = true;
		assert.ok(Math.abs(normAngle(j.angle - j.trailer.angle)) <= MAX_ARTICULATION + 1e-9,
			'fold must stay inside the limit, frame ' + i);
	}
	assert.ok(sawOvershoot, 'stepRig must report articulation past the limit');

	// Frame-rate independence: the same second of driving must land in the same place whether
	// it is simulated at 60Hz or 144Hz. This is the whole point of the dt refactor.
	var slow = makeRig(0, 0, 0), fast = makeRig(0, 0, 0);
	for (i = 0; i < 60; i++) stepRig(slow, 1, 1, 1 / 60);
	for (i = 0; i < 144; i++) stepRig(fast, 1, 1, 1 / 144);
	assert.ok(Math.hypot(slow.x - fast.x, slow.y - fast.y) < 2,
		'60Hz and 144Hz must agree within 2px, got ' + Math.hypot(slow.x - fast.x, slow.y - fast.y).toFixed(2));
	assert.ok(Math.abs(normAngle(slow.angle - fast.angle)) < 0.03, 'headings must agree across refresh rates');

	// The lot must not park trucks inside each other, and the player must not start in one.
	var lot = buildLot(LEVEL);
	var obs = lotObstacles(lot);
	var nParked = lot.parked.length;   // walls legitimately overlap each other at the corners
	for (i = 0; i < nParked; i++)
		for (var j = i + 1; j < obs.length; j++)
			assert.ok(!intersects(obs[i], obs[j]), 'lot obstacles ' + i + ' and ' + j + ' overlap');

	var p = makeRig(LEVEL.start.x, LEVEL.start.y, LEVEL.start.angle);
	rigBoxes(p).forEach(function (pb, k) {
		obs.forEach(function (o, m) { assert.ok(!intersects(pb, o), 'player part ' + k + ' starts inside obstacle ' + m); });
	});

	// The bay must actually be empty and reachable-shaped: a trailer parked there hits nothing.
	var parkedTrailer = getBoxCorners(lot.bay.trailerX, lot.bay.trailerY, TRUCK.trailerLen, TRUCK.trailerWid, lot.bay.angle);
	obs.forEach(function (o, m) { assert.ok(!intersects(parkedTrailer, o), 'parked-in-bay trailer overlaps obstacle ' + m); });

	console.log('core.js self-check OK');
}
