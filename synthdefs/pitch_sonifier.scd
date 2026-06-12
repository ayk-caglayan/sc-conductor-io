// Pitch Sonifier - Plays a sustained sine tone at a given frequency
// Used to sonify stored pitch trajectory data (one synth per pitch point)
// Uses ASR envelope with gate control
//
// @meta: (
//   name: \pitchSonifier,
//   displayName: "Pitch Sonifier",
//   parameters: [
//     (name: \amp,         default: 0.2,  min: 0.0,   max: 1.0,  type: \float, label: "Amplitude"),
//     (name: \attackTime,  default: 0.005,min: 0.001, max: 1.0,  type: \float, label: "Attack (s)"),
//     (name: \releaseTime, default: 0.15, min: 0.01,  max: 5.0,  type: \float, label: "Release (s)")
//   ]
// )

SynthDef(\pitchSonifier, {
	arg freq = 440,
	    amp = 0.2,
	    gate = 1,
	    outBus = 0,
	    attackTime = 0.005,
	    releaseTime = 0.15;

	var sig, env;

	env = EnvGen.kr(
		Env.asr(attackTime, 1.0, releaseTime),
		gate,
		doneAction: 2
	);

	sig = SinOsc.ar(freq) * amp * env;

	Out.ar(outBus, sig ! 2);
}).add;
