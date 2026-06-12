// Buffer Sequencer - Plays a single audio buffer with timed playback and fade envelope
// Compatible with buffers recorded by \bufferRecordInput
// Supports playback rate modulation via a slow sine LFO for variation
//
// @meta: (
//   name: \bufferSequencer,
//   displayName: "Buffer Sequencer",
//   parameters: [
//     (name: \bufRate,    default: 1.0,  min: 0.25, max: 4.0,  type: \float, label: "Playback Rate"),
//     (name: \ampScale,   default: 0.6,  min: 0.0,  max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \pan,        default: 0.0,  min: -1.0, max: 1.0,  type: \float, label: "Pan"),
//     (name: \rateModAmt, default: 0.0,  min: 0.0,  max: 0.5,  type: \float, label: "Rate Mod Amount"),
//     (name: \rateModHz,  default: 0.1,  min: 0.01, max: 2.0,  type: \float, label: "Rate Mod Speed (Hz)"),
//     (name: \attack,     default: 0.01, min: 0.001,max: 2.0,  type: \float, label: "Attack (s)"),
//     (name: \release,    default: 0.2,  min: 0.01, max: 5.0,  type: \float, label: "Release (s)")
//   ]
// )

SynthDef(\bufferSequencer, {
	arg bufNum = 0,
	    outBus = 0,
	    bufRate = 1.0,
	    ampScale = 0.6,
	    pan = 0,
	    rateModAmt = 0.0,
	    rateModHz = 0.1,
	    attack = 0.01,
	    release = 0.2,
	    startPos = 0,
	    durSec = 4.0;

	var sig, env, rate, playbackPos, sustainTime;

	sustainTime = (durSec - attack - release).max(0.01);

	env = EnvGen.kr(
		Env.linen(attack, sustainTime, release, 1, \sin),
		doneAction: 2
	);

	rate = bufRate * BufRateScale.ir(bufNum);
	// Add optional slow LFO modulation to rate
	rate = rate + (SinOsc.kr(rateModHz) * rateModAmt * bufRate);

	playbackPos = BufFrames.ir(bufNum) * startPos;

	sig = PlayBuf.ar(
		1,
		bufNum,
		rate,
		1,
		playbackPos,
		1,
		doneAction: 0
	);

	sig = sig * env * ampScale;
	sig = Pan2.ar(sig, pan);

	Out.ar(outBus, sig);
}).add;
