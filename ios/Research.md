# Research notes

Three areas Jan flagged after the first build on the iPad: the sound is a chiptune, the blue
frame is noise and the floor is not asphalt, the trucks are flat and repetitive. Three
researchers looked at each. This file keeps what survived, with the links checked.

## What can be done from this machine

Linux, no Xcode, no DAW, no drawing tool. Available: Pillow, numpy and Pillow in a venv,
pycairo, ImageMagick, ffmpeg, and downloads by URL. So: art can be baked offline in Python and
previewed as images before it ships. Sound can be rendered offline but not heard here.

## 1. Floor and the infinite lot

**Findings**

- SpriteKit noise textures cannot read as asphalt. A real CC0 asphalt tile can.
- From a drone height, asphalt reads as a smooth, mottled dark surface with patches, seams,
  stains and long cracks. The grain is invisible. So the base tile must be the mottled kind,
  not the coarse kind, and the mid-scale variation is what sells it.
- Tiles looked at, all CC0, no attribution: ambientCG Asphalt002 (coarse, light: no),
  Asphalt004 (smooth, mottled: yes, the base), Asphalt023S (fine speckle: a faint grain layer),
  Poly Haven asphalt_01 (uniform brown-grey: possible base), asphalt_02 (strong cracks that
  repeat every tile: no). Download pattern: `https://ambientcg.com/get?file=Asphalt004_1K-JPG.zip`,
  `https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/asphalt_01/asphalt_01_diff_2k.jpg`.
  One 1024 tile re-saved as JPEG is about 200 KB.
- `SKTileMapNode` with one tile group and four pre-rotated tile definitions is one draw call,
  has no seams, and breaks the repeat without a shader. A custom `SKShader` with `fract()` also
  works but only on a texture that is not in an atlas. Grids of sprites: no.
- `SKLightNode` with normal maps is not worth it here. Fake the lamps with additive gradients,
  a multiply darkness layer and static shadow polygons.
- Decals baked offline read far better than vector fills: oil stains as stacked blurred
  ellipses, cracks as noise-warped tapered polylines, tyre marks as a rubber-noise strip along
  a curve, puddles as a soft sheen. 3DTexel has 280 CC0 PBR decals at
  `https://3dtexel.com/decals/` if hand-made ones fall short.

**Recommendation, bottom to top**

1. Tiled asphalt, Asphalt004 darkened for night, four rotations, covering three times the lot.
2. Large-scale multiply layer to break the tiling.
3. Cracks, oil stains, tyre marks, puddles: baked decal PNGs scattered by seed.
4. Stall lines with alpha-eroded edges.
5. Sodium lamp pools, true sodium colour, two gradients per lamp, static long shadows from
   the lamp posts.
6. Camera-pinned vignette so the lot darkens into night at the screen edge.
7. `SKCameraNode` zoomed out a few percent so a strip of the outer asphalt shows.

**The edge.** The walls go as pictures. What the collision edge becomes is a choice:

- Open lot: no walls at all. The asphalt goes on. Driving out of the lit area is allowed and
  pointless. Honest, and the "infinite" feel the brief asks for. Recommended.
- Kerb: keep the collision edge, draw it as a worn painted line. A scrape on it ends the run.
  Honest, but it is still a hard edge in an infinite lot.

Both are cheap. Ship both behind an option and pick by play.

**Effort:** about a day.

## 2. Trucks

**Findings**

- No free sprite pack has a true top-down semi with a separate trailer at this size. Kenney's
  Racing Pack and Pixel Vehicle Pack have cars. OpenGameArt has one car pack with a plain
  truck. The one candidate, `https://marcusvh.itch.io/2d-cars`, is a pixel-art pack of unknown
  size. Stop looking.
- `SKLightNode` with normal maps is out: normal vectors do not rotate with `zRotation`
  (Apple Developer Forums thread 24523, confirmed as a bug), and the trucks rotate freely.
  Shading baked into the texture is correct at every angle and costs nothing per frame.
- The 28 x 24 cab box is nearly square. That is an EU cab-over. A US long-nose needs a longer
  box, which is a physics and lot change, not an art change.
- Repetition is a variation problem, not a shading problem. Real depots have fleets: two or
  three trailers sharing a colour, a name and a logo.

**Recommendation**

Bake the truck art offline in Python with Pillow, preview it here as images, and ship PNGs.
The Swift side then only swaps `SKShapeNode` bodies for `SKSpriteNode` textures. Runtime
Core Graphics would give the same picture with no way to see it before it ships.

Per trailer, in order: livery fill, roof gradient across the short axis (white 0.14 at the
lamp edge to black 0.18 at the far edge), rib shadow pairs, ambient-occlusion outline, lamp-side
highlight, a screen-blend reflection strip, dirt noise multiplied at 0.05 to 0.2, rust and scuff
blotches by age, stripe, fleet name in a condensed face, logo mark. The drop shadow is a separate
blurred sprite behind the body, so the body texture stays exactly the collision box.

Per cab: the same, with a stronger gradient, a windscreen with a diagonal glass streak, mirrors,
a lighter hood band for the "conventional" look.

Variation, seeded per truck: trailer type (dry van 40%, reefer with a nose unit 15%,
curtainsider 15%, flatbed with a tarped load 15%, tanker 10%, container 5%), colour (white 35%,
silver 20%, dark blue 15%, red 15%, green 10%, other 5%), stripe 30%, name 50%, dirt skewed
light. Two or three trucks per fleet. About 12 trailer and 8 cab textures at 520 x 140 and
150 x 130 device pixels, under 1 MB in total.

Player truck: the steered wheels stay as separate sprites with a tread texture and the 1.6x
readout, the tail lamps stay as separate sprites so brake and reverse keep working, a kingpin
mark is baked at the fold pivot, wheels spin with speed.

**Effort:** two days, half of it looking at previews.

## 3. Sound

**Findings**

- The synth is a sum of four sines. An engine is a pulse train at the firing rate
  (RPM / 60 x cylinders / 2), with per-cylinder jitter, through a body resonance around
  150 to 400 Hz and an exhaust low-pass that closes as RPM drops, plus a rattle: noise
  amplitude-modulated by the same pulses. That is what reads as diesel. References: Baldan et
  al. 2015, the SDT `motor~` object (`https://github.com/SkAT-VG/SDT`),
  `https://github.com/DasEtwas/enginesound`.
- Modern games crossfade a few loops by load, pitching each only about 20% from its centre.
  BOOM Library's primer says loops every 500 RPM, crossfade half the spacing, never pitch more
  than 500 RPM. For a one-gear truck: idle, low load, high load, and a quiet coast layer that
  fades in when the throttle drops. Equal-power crossfade, not linear.
- Real recordings, checked, CC0, no login: BigSoundBank truck horn
  `https://www.bigsoundbank.com/UPLOAD/mp3/2721.mp3` (3 s, 55 KB) and reverse beeper
  `https://www.bigsoundbank.com/UPLOAD/mp3/1914.mp3` (20 s, 771 KB, itself a synthesised
  1220 Hz tone). Kenney has no engine or horn audio. freesound has CC0 diesel idles
  (C-V 565598, qubodup 187564) but needs an account and an OAuth token to download by script.
  BBC RemArc is non-commercial: never. Sonniss bundles are 7 GB: no.
- Crash: three cheap layers sound expensive. A 5 to 10 ms noise transient, two to four decaying
  inharmonic partials at 200 to 500 Hz, and a sparse train of debris ticks over a second. The
  jam clunk is the same primitives, shorter. Air-brake hiss on every stop: band-passed noise,
  20 ms attack, half a second decay. That hiss is the most truck-like sound of all.
- `AVAudioUnitVarispeed` per loop, not `AVAudioUnitTimePitch`, which adds 90 ms of latency and
  crackles on rate change. Volume has no ramp of its own: approach the target over 50 to 100 ms
  every frame. An `AVAudioUnitEQ` low-pass driven by throttle, a shared reverb at 10 to 15%.

**Recommendation**

1. Render the diesel model offline in Python into four loops and ship them through the sample
   engine with the crossfade graph. Same waveform model into the render block for the Synth
   option, so both improve and the switch stays meaningful.
2. Layered crash and clunk, air-brake hiss, turbo whine: synthesised.
3. Horn and beeper: the two BigSoundBank recordings, trimmed with ffmpeg.
4. Ambient bed last. It is the hardest to fake. A CC0 recording needs a freesound account,
   which is a Jan task, or it stays synthesised.

**Effort:** a day and a half. Nothing can be heard from here, so each step ships and Jan
listens.

## Order

Floor and edge first: the largest change for the least work, and it can be previewed here.
Trucks second. Sound third. Each step is a commit, a test on the iPad, and feedback.

---

## Appendix: the first two sound engines, and why

Research notes behind `App/SoundEngine.swift`. Both options are built and switchable in the
Options sheet. Written from a survey of the Apple audio APIs for iOS 16+.

## Option A: synthesis in a render block (shipped as "Synth")

- APIs: `AVAudioEngine`, `AVAudioSourceNode` with a render block, `AVAudioSession`.
- No files. Every sound is computed per sample: a harmonic stack for the diesel, a gated tone
  for the reverse beeper, a noise burst for the crash, a two-tone horn for the win.
- The render block runs on the real-time audio thread. Rules: no locks, no allocation, no
  Objective-C calls, no printing. All state is pre-allocated in the voice object.
- Control values (speed, throttle, reversing) are stored once per frame by the game and loaded
  by the render block through `Synchronization.Atomic` with relaxed ordering. No locks, no
  waiting on either side. The deployment target is iOS 26, so the module is available.
- One-shots are trigger counters: the render block compares the counter to the last value it
  saw and starts an envelope.
- Format: `AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)`, non-interleaved
  Float32. The main mixer upmixes to stereo.
- Session: `.ambient` with `.mixWithOthers`. The mute switch silences it, music keeps playing.
- CPU: under 1% on any recent iPad.
- Size: about 200 lines.

## Option B: samples through a varispeed unit (shipped as "Samples")

- APIs: `AVAudioPlayerNode` -> `AVAudioUnitVarispeed` -> main mixer, inside the same
  `AVAudioEngine`. `scheduleBuffer(_:at:options: .loops)` for the loops, `.interrupts` for
  one-shots.
- `AVAudioUnitVarispeed.rate` changes pitch and tempo together, which is what an engine does.
  `AVAudioUnitTimePitch` would change pitch alone at a little more CPU, if the "chipmunk" at
  high rate bothers anyone.
- Files: WAV, 16-bit PCM mono at 22050 Hz, generated by `tools/make_sounds.py`. iOS reads
  WAV directly. `.caf` is not needed.
- Seamless loops: the engine loop is a stack of harmonics of 40 Hz over exactly 1 s, so every
  partial completes whole cycles. The ambient bed is brown noise with its tail crossfaded into
  its head.
- CPU: negligible.
- Size: about 150 lines of Swift plus the 100-line generator script.

## Rejected

- `SKAction.playSoundFileNamed`: no pitch, no volume, no stop. Fine for a one-shot jingle,
  useless for a speed-following engine loop.
- `AVAudioPlayer` with `enableRate`: works, rate 0.5 to 2.0, but it is a subset of option B
  and not a different engine, so it would not earn a switch.
- `SKAudioNode`: positional audio in scene space. The camera does not move, so there is
  nothing to position. Also the least maintained corner of SpriteKit.
- `CoreHaptics`: does not apply. iPads have no Taptic Engine and
  `CHHapticEngine.capabilitiesForHardware().supportsHaptics` is false on every model.

## Gotchas

- Backgrounding stops the audio session. The scene stops and restarts the engine on
  `UIApplication.didBecomeActiveNotification`.
- A stopped `AVAudioPlayerNode` drops its scheduled buffers. Loops are rescheduled on every
  start.
- Interruptions (a phone call on a cellular iPad) end the session. Not handled yet. Observe
  `AVAudioSession.interruptionNotification` and restart on `.ended` with `.shouldResume` when
  it matters.
- The simulator's audio callbacks differ from a device. Test on the iPad.

## Free samples, if real recordings are wanted later

- freesound.org with the CC0 filter. qubodup's "Truck Engine Idle Loops" is CC0.
- kenney.nl: Impact Sounds and Digital Audio packs, all CC0. No truck horn there.
- bigsoundbank.com: royalty-free truck recordings, check per-file terms.
