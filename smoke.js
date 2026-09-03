// smoke.js — runs index.html's script against a stub canvas. `node smoke.js`
// core.js's own check cannot see the page wiring, and that is where the bugs have been.

var fs = require('fs'), vm = require('vm'), assert = require('assert');
var dir = __dirname + '/';
var page = fs.readFileSync(dir + 'index.html', 'utf8').match(/<script>\n([\s\S]*?)<\/script>/g).pop().replace(/<\/?script>/g, '');

var noop = function () {};
var ctx = new Proxy({}, {
	get: function (t, k) {
		if (k === 'createRadialGradient' || k === 'createLinearGradient') return function () { return { addColorStop: noop }; };
		if (k === 'measureText') return function () { return { width: 10 }; };
		return typeof k === 'string' && k in t ? t[k] : noop;
	},
	set: function () { return true; }
});
function el() {
	var e = { innerText: '', innerHTML: '', className: '', style: {}, width: 850, height: 650, children: [],
		classList: { add: noop, remove: noop }, addEventListener: noop,
		getContext: function () { return ctx; },
		appendChild: function (c) { e.children.push(c); return c; } };
	return e;
}

// Capture the key handlers instead of dropping them. They were noop'd, so every key the page
// binds was untested -- which is how T shipped with no visible effect while driving forward.
var handlers = {};
var sandbox = { document: { getElementById: el, createElement: el }, requestAnimationFrame: noop, console: console };
sandbox.window = sandbox;
sandbox.window.addEventListener = function (type, fn) { (handlers[type] = handlers[type] || []).push(fn); };
function press(k) { handlers.keydown.forEach(function (fn) { fn({ key: k, preventDefault: noop }); }); }
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(dir + 'core.js', 'utf8'), sandbox, { filename: 'core.js' });
vm.runInContext(page, sandbox, { filename: 'index.html' });

// The page must be fully initialised once its script has run. A loop started before
// initGame() throws on frame 1 and silently kills everything after it.
assert.ok(sandbox.rig, 'rig must exist after the page script runs');
assert.ok(sandbox.lot && sandbox.lot.bay, 'lot must be built after the page script runs');
assert.strictEqual(sandbox.isGameOver, false, 'must not start in a game-over state');
assert.strictEqual(sandbox.presetBar.children.length, sandbox.PRESETS.length, 'every preset must get a button');

// Every key the page binds must actually do something. These were untested: addEventListener was
// a noop, so a dead key looked exactly like a working one.
assert.ok(handlers.keydown && handlers.keydown.length, 'the page must bind a keydown handler');

// Reversing at full lock into the fold stop must raise the jam flag and keep drawing, and pulling
// forward must clear it. Without the flag, pushing reverse against the stop is indistinguishable
// from a dead key: the step is refused, so absolutely nothing happens on screen.
sandbox.initGame(0);
sandbox.obstacleBoxes = [];      // the lot is tight enough that it crashes long before it folds
sandbox.keys.down = true; sandbox.keys.right = true;
for (var j = 0; j < 600 && !sandbox.isJammed; j++) { sandbox.update(1 / 60); sandbox.draw(); }
assert.ok(sandbox.isJammed, 'reversing at full lock must raise the jam flag');
assert.ok(!sandbox.isGameOver, 'a jam must not end the run');
sandbox.draw();
sandbox.keys.down = false; sandbox.keys.right = false; sandbox.keys.up = true;
for (j = 0; j < 120; j++) sandbox.update(1 / 60);
assert.ok(!sandbox.isJammed, 'pulling forward must clear the jam flag');
sandbox.keys.up = false;
sandbox.initGame(0);

// R restarts, and the preset keys switch preset.
sandbox.shifts = 7;
press('r');
assert.strictEqual(sandbox.shifts, 0, 'R must restart the run');
press(sandbox.PRESETS[2].key);
assert.strictEqual(sandbox.activePreset, 2, 'a preset key must switch preset');
press(sandbox.PRESETS[0].key);

// Drive every preset: switching preset must leave a clean, playable state, and every branch of
// update() and draw() must survive real input at every zoom.
var pressed = [{}, { up: 1 }, { down: 1 }, { up: 1, left: 1 }, { down: 1, right: 1 }, { down: 1, left: 1 }];
sandbox.PRESETS.forEach(function (p, pi) {
	sandbox.initGame(pi);
	var tag = ' [preset ' + p.name + ']';
	assert.ok(sandbox.rig && !sandbox.isGameOver, 'preset switch must leave a live rig' + tag);

	for (var i = 0; i < 900; i++) {
		var q = pressed[Math.floor(i / 150) % pressed.length];
		sandbox.keys.up = !!q.up; sandbox.keys.down = !!q.down;
		sandbox.keys.left = !!q.left; sandbox.keys.right = !!q.right;
		sandbox.update(1 / 60);
		sandbox.draw();
		assert.ok(Number.isFinite(sandbox.rig.x) && Number.isFinite(sandbox.rig.trailer.angle),
			'rig went non-finite on frame ' + i + tag);
		if (sandbox.isGameOver) sandbox.initGame(pi);
	}

	// A rig placed correctly in the bay and stopped must register as parked, at every zoom --
	// the win tolerance scales with the rig, so a fixed pixel tolerance would silently break here.
	sandbox.initGame(pi);
	sandbox.rig.trailer.angle = sandbox.lot.bay.angle;
	sandbox.rig.trailer.x = sandbox.lot.bay.trailerX;
	sandbox.rig.trailer.y = sandbox.lot.bay.trailerY;
	sandbox.rig.speed = 0;
	sandbox.checkParked();
	assert.ok(sandbox.isGameOver, 'a correctly parked, stopped rig must win' + tag);
});

console.log('smoke.js OK across ' + sandbox.PRESETS.length + ' presets');
