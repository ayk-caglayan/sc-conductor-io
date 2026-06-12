// Pitch Shift SynthDef
// Reads live audio from inBus (or SoundIn) and applies PitchShift.
// The pitch ratio can be set at creation or modulated. Uses a gate-controlled
// ASR envelope for clean start/stop.
//
// For FX chain use: set useSoundIn=0 and inBus to the private bus index.
//
// @meta: (
//   name: \pitchShiftSynth,
//   displayName: "Pitch Shift",
//   parameters: [
//     (name: \pitchRatio,  default: 1.0,  min: 0.25, max: 4.0,  type: \float, label: "Pitch Ratio"),
//     (name: \windowSize,  default: 0.2,  min: 0.01, max: 1.0,  type: \float, label: "Window Size (s)"),
//     (name: \pitchDisp,   default: 0.0,  min: 0.0,  max: 1.0,  type: \float, label: "Pitch Dispersion"),
//     (name: \timeDisp,    default: 0.0,  min: 0.0,  max: 1.0,  type: \float, label: "Time Dispersion"),
//     (name: \amp,         default: 0.5,  min: 0.0,  max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \pan,         default: 0.0,  min: -1.0, max: 1.0,  type: \float, label: "Pan"),
//     (name: \attack,      default: 0.01, min: 0.001,max: 2.0,  type: \float, label: "Attack (s)"),
//     (name: \release,     default: 0.3,  min: 0.01, max: 5.0,  type: \float, label: "Release (s)")
//   ]
// )

SynthDef(\pitchShiftSynth, {
	arg inBus = 0,
	    useSoundIn = 1,    // 1 = SoundIn.ar(inBus), 0 = In.ar(inBus) for FX chain
	    outBus = 0,
	    pitchRatio = 1.0,
	    windowSize = 0.2,
	    pitchDisp = 0.0,
	    timeDisp = 0.0,
	    amp = 0.5,
	    pan = 0,
	    gate = 1,
	    attack = 0.01,
	    release = 0.3;

	var dry, sig, env;

	dry = Select.ar(useSoundIn, [In.ar(inBus, 1), SoundIn.ar(inBus)]);

	sig = PitchShift.ar(
		dry,
		windowSize,
		pitchRatio,
		pitchDisp,
		timeDisp
	);

	env = EnvGen.kr(
		Env.asr(attack, 1, release),
		gate,
		doneAction: 2
	);

	sig = sig * env * amp;
	sig = Pan2.ar(sig, pan);

	Out.ar(outBus, sig);
}).add;
