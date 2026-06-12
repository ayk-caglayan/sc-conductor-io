// JSON Note Percussive Output SynthDef
// Designed for json_note_output_template.scd note events.
//
// @meta: (
//   name: \jsonNotePercOutputSynth,
//   displayName: "JSON Note Perc Output",
//   parameters: [
//     (name: \freq,      default: 440,  min: 40,   max: 8000, type: \float, label: "Frequency (Hz)"),
//     (name: \pitch,     default: 60,   min: 0,    max: 127,  type: \float, label: "Pitch (MIDI)"),
//     (name: \amp,       default: 0.3,  min: 0,    max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \durSec,    default: 0.2,  min: 0.01, max: 8.0,  type: \float, label: "Duration (s)"),
//     (name: \pan,       default: 0.0,  min: -1.0, max: 1.0,  type: \float, label: "Pan"),
//     (name: \tone,      default: 0.65, min: 0.0,  max: 1.0,  type: \float, label: "Tone"),
//     (name: \noiseMix,  default: 0.35, min: 0.0,  max: 1.0,  type: \float, label: "Noise Mix"),
//     (name: \envType,   default: 1,    min: 0,    max: 6,    type: \int,   label: "Env Type (0-6)"),
//     (name: \envAttack, default: 0.01, min: 0.001,max: 5.0,  type: \float, label: "Env Attack (s)"),
//     (name: \envDecay,  default: 0.08, min: 0.001,max: 5.0,  type: \float, label: "Env Decay (s)"),
//     (name: \envSustain,default: 0.7,  min: 0.0,  max: 1.0,  type: \float, label: "Env Sustain"),
//     (name: \envRelease,default: 0.08, min: 0.001,max: 5.0,  type: \float, label: "Env Release (s)"),
//     (name: \envLevel,  default: 1.0,  min: 0.0,  max: 2.0,  type: \float, label: "Env Level"),
//     (name: \envCurve,  default: -4.0, min: -8.0, max: 8.0,  type: \float, label: "Env Curve")
//   ]
// )
SynthDef(\jsonNotePercOutputSynth, {
	arg outBus = 0,
	    freq = 440,
	    pitch = 60,
	    amp = 0.3,
	    durSec = 0.2,
	    pan = 0,
	    tone = 0.65,
	    noiseMix = 0.35,
	    envType = 1,      // 0=perc,1=linen,2=triangle,3=sine,4=asr,5=adsr,6=cutoff
	    envAttack = 0.01,
	    envDecay = 0.08,
	    envSustain = 0.7,
	    envRelease = 0.08,
	    envLevel = 1.0,
	    envCurve = -4.0;

	var effectiveFreq, env, sustainSec, holdSec;
	var pitched, noisy, sig;

	effectiveFreq = Select.kr((freq > 0).asInteger, [pitch.midicps, freq]).clip(20, 12000);
	sustainSec = (durSec - envAttack - envRelease).max(0.001);
	holdSec = (durSec - envAttack - envDecay - envRelease).max(0.001);

	env = EnvGen.kr(
		Select.kr(envType.clip(0, 6), [
			Env.perc(envAttack, (durSec - envAttack).max(0.001), envLevel, envCurve),
			Env.linen(envAttack, sustainSec, envRelease, envLevel, envCurve),
			Env.triangle(durSec.max(0.002), envLevel),
			Env.sine(durSec.max(0.002), envLevel),
			Env.linen(envAttack, sustainSec, envRelease, envLevel, envCurve),
			Env([0, envLevel, envLevel * envSustain, 0], [envAttack, envDecay + holdSec, envRelease], envCurve),
			Env([0, envLevel, envLevel, 0], [0.001, (durSec - envRelease).max(0.001), envRelease], envCurve)
		]),
		doneAction: 2
	);

	// Simple percussive timbre: short pitched body + bright noise transient.
	pitched = SinOsc.ar(effectiveFreq * [1, 1.005]).sum * (tone * 0.6);
	noisy = HPF.ar(WhiteNoise.ar(0.6), effectiveFreq * 1.5) * noiseMix;
	sig = (pitched + noisy) * env * amp;
	sig = LeakDC.ar(sig);
	Out.ar(outBus, Pan2.ar(sig, pan));
}).add;
