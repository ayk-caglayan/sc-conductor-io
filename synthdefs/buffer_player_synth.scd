// Buffer Play Output SynthDef
// Plays back audio buffers with rate and pan control
//
// Args:
//   bufNum: buffer number to play
//   amp: amplitude scaling (0-1)
//   pan: stereo pan position (-1 to 1)
//   bufRate: playback rate multiplier (1.0 = normal speed)
//   startPos: start position in buffer (0-1 normalized)
//   durSec: duration in seconds (for ASR envelope sustain time)
//   attack: envelope attack time in seconds
//   release: envelope release time in seconds
//
// @meta: (
//   name: \bufferPlayOutputSynth,
//   displayName: "Buffer Player",
//   parameters: [
//     (name: \amp,      default: 0.5,  min: 0.0, max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \pan,      default: 0.0,  min: -1.0, max: 1.0, type: \float, label: "Pan"),
//     (name: \bufRate,  default: 1.0,  min: 0.1, max: 4.0,  type: \float, label: "Playback Rate"),
//     (name: \startPos, default: 0.0,  min: 0.0, max: 1.0,  type: \float, label: "Start Position (0-1)"),
//     (name: \durSec,   default: 4.0,  min: 0.1, max: 120.0,type: \float, label: "Duration (s)"),
//     (name: \attack,   default: 0.01, min: 0.001,max: 5.0, type: \float, label: "Attack (s)"),
//     (name: \release,  default: 0.1,  min: 0.001,max: 5.0, type: \float, label: "Release (s)")
//   ]
// )

SynthDef(\bufferPlayOutputSynth, {
	arg bufNum = 0,          // Buffer number to play
	    outBus = 0,          // Output bus (0 = hardware out, or private bus for FX chain)
	    amp = 0.5,           // Amplitude scaling
	    pan = 0,             // Stereo pan (-1 to 1)
	    bufRate = 1.0,       // Playback rate (speed multiplier)
	    startPos = 0,        // Start position in buffer (0-1 normalized)
	    durSec = 4.0,        // Duration in seconds (total duration including attack and release)
	    attack = 0.01,       // Envelope attack time in seconds
	    release = 0.1;       // Envelope release time in seconds

	var sig, playbackPos, env, sustainTime;

	// Calculate start position in frames
	playbackPos = startPos * BufFrames.ir(bufNum);

	// Calculate sustain time (total duration minus attack and release)
	sustainTime = (durSec - attack - release).max(0.01);

	// Use Env.linen for attack-sustain-release envelope with fixed duration
	// This automatically frees the synth after the envelope completes
	env = EnvGen.kr(
		Env.linen(attack, sustainTime, release, 1, \sin),
		doneAction: 2
	);

	// PlayBuf with doneAction: 0 (envelope handles synth freeing)
	sig = PlayBuf.ar(
		1,                        // Fixed channel count (mono)
		bufNum,                   // Which buffer to play
		bufRate * BufRateScale.ir(bufNum),  // Playback rate with sample-rate correction
		1,                        // Trigger (1 = always playing)
		playbackPos,              // Start position in frames
		1,                        // Loop flag (1 = looping, envelope controls duration)
		doneAction: 0             // Don't free synth (envelope handles this)
	);

	// Apply envelope and amplitude, then stereo pan
	sig = sig * env * amp;
	sig = Pan2.ar(sig, pan);

	Out.ar(outBus, sig);
}).add;
