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

var MAX_ARTICULATION = 1.45; // ~83 degrees, then the cab is into the trailer nose

function makeRig(x, y, angle) {
	var r = {
		x: x, y: y, angle: angle, speed: 0, steer: 0,
		wheelbase: 34, maxSpeed: 1.8, reverseFactor: 0.55,
		accel: 0.04, friction: 0.035, maxSteer: 0.65, steerRate: 0.045,
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

function stepRig(r, drive, steerInput) {
	// Caster self-aligning torque scales with speed, so a stopped rig holds its wheel where
	// you left it. That is what lets you set the angle before shifting into reverse.
	if (steerInput) r.steer = clamp(r.steer + steerInput * r.steerRate, -r.maxSteer, r.maxSteer);
	else r.steer = towardZero(r.steer, r.steerRate * 1.5 * Math.min(1, Math.abs(r.speed) / r.maxSpeed));

	if (drive > 0) r.speed = Math.min(r.speed + r.accel, r.maxSpeed);
	else if (drive < 0) r.speed = Math.max(r.speed - r.accel, -r.maxSpeed * r.reverseFactor);
	else r.speed = towardZero(r.speed, r.friction);

	r.angle = normAngle(r.angle + (r.speed / r.wheelbase) * Math.tan(r.steer));
	r.x += Math.cos(r.angle) * r.speed;
	r.y += Math.sin(r.angle) * r.speed;

	var t = r.trailer;
	t.angle = normAngle(t.angle + (r.speed / t.kingpinToAxle) * Math.sin(r.angle - t.angle));
	syncTrailer(r);

	return normAngle(r.angle - t.angle);
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
	for (var i = 0; i < 400; i++) stepRig(r, 1, 0);
	assert.ok(Math.abs(normAngle(r.angle - r.trailer.angle)) < 0.05, 'forward must converge, got ' + normAngle(r.angle - r.trailer.angle));

	// Reverse is unstable: the whole point of the game.
	var b = makeRig(400, 300, 0);
	b.trailer.angle = 0.05;
	var art0 = Math.abs(normAngle(b.angle - b.trailer.angle));
	for (i = 0; i < 200; i++) stepRig(b, -1, 0);
	assert.ok(Math.abs(normAngle(b.angle - b.trailer.angle)) > art0 * 3, 'reverse must diverge');

	// Dry steering: the wheel holds its angle at a standstill, and a stopped rig never rotates.
	var s = makeRig(0, 0, 0);
	for (i = 0; i < 10; i++) stepRig(s, 0, 1);
	var held = s.steer;
	assert.ok(held > 0.3, 'wheel must turn while stopped');
	for (i = 0; i < 30; i++) stepRig(s, 0, 0);
	assert.strictEqual(s.steer, held, 'wheel must hold its angle at a standstill');
	assert.strictEqual(s.angle, 0, 'a stopped rig must not rotate');

	// Rolling, it still self-centres when you let go.
	var m = makeRig(0, 0, 0);
	for (i = 0; i < 30; i++) stepRig(m, 1, 1);
	var atSpeed = Math.abs(m.steer);
	for (i = 0; i < 80; i++) stepRig(m, 1, 0);
	assert.ok(Math.abs(m.steer) < atSpeed * 0.2, 'wheel must self-centre while rolling');

	// No NaN anywhere (the old build produced a NaN trailer on frame 1 and never recovered).
	var n = makeRig(LEVEL.start.x, LEVEL.start.y, LEVEL.start.angle);
	assert.ok(finite(n) && finite(n.trailer), 'rig must be finite at init');
	for (i = 0; i < 600; i++) stepRig(n, i % 120 < 60 ? 1 : -1, Math.sin(i / 40) > 0 ? 1 : -1);
	assert.ok(finite(n) && finite(n.trailer), 'rig must stay finite');

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
