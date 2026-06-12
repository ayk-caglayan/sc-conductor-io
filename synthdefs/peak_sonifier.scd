// Peak Sonifier - Creates sustained sine tones at detected spectral peak frequencies
// Requires \sineFeature input as source
// Uses ASR envelope with gate control for flexible duration
//
// @meta: (
//   name: \peakSonifier,
//   displayName: "Peak Sonifier",
//   parameters: [
//     (name: \amp,     default: 0.1,  min: 0.0, max: 1.0,  type: \float, label: "Amplitude"),
//     (name: \pan,     default: 0.0,  min: -1.0, max: 1.0, type: \float, label: "Pan"),
//     (name: \attack,  default: 0.01, min: 0.001,max: 2.0, type: \float, label: "Attack (s)"),
//     (name: \release, default: 0.3,  min: 0.01, max: 5.0, type: \float, label: "Release (s)")
//   ]
// )

SynthDef(\peakSonifier, {
	arg freq = 440,
	    amp = 0.1,
	    pan = 0,
	    gate = 1,
	    outBus = 0,
	    attack = 0.01,
	    release = 0.3;

	var sig, env;

	env = EnvGen.kr(
		Env.asr(attack, 1.0, release),
		gate,
		doneAction: 2
	);

	sig = SinOsc.ar(freq) * amp * env;
	sig = Pan2.ar(sig, pan);

	Out.ar(outBus, sig);
}).add;
