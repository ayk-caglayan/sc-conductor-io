// Onset Slicer - Plays a segment of a buffer starting at a given onset position
// Requires onset-indexed buffer data from a future \onsetRecordInput
// Each synth plays one slice; the routine creates one synth per slice index
//
// @meta: (
//   name: \onsetSlicer,
//   displayName: "Onset Slicer",
//   parameters: [
//     (name: \bufRate,    default: 1.0,  min: 0.25, max: 4.0,  type: \float, label: "Playback Rate"),
//     (name: \ampScale,   default: 0.6,  min: 0.0,  max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \pan,        default: 0.0,  min: -1.0, max: 1.0,  type: \float, label: "Pan"),
//     (name: \attack,     default: 0.005,min: 0.001,max: 1.0,  type: \float, label: "Attack (s)"),
//     (name: \release,    default: 0.15, min: 0.01, max: 3.0,  type: \float, label: "Release (s)")
//   ]
// )

SynthDef(\onsetSlicer, {
	arg bufNum = 0,
	    outBus = 0,
	    startFrame = 0,     // Start frame within the buffer (in frames)
	    durSec = 1.0,       // Duration to play
	    bufRate = 1.0,
	    ampScale = 0.6,
	    pan = 0,
	    attack = 0.005,
	    release = 0.15;

	var sig, env, rate, sustainTime;

	sustainTime = (durSec - attack - release).max(0.01);

	env = EnvGen.kr(
		Env.linen(attack, sustainTime, release, 1, \sin),
		doneAction: 2
	);

	rate = bufRate * BufRateScale.ir(bufNum);

	sig = PlayBuf.ar(
		1,
		bufNum,
		rate,
		1,
		startFrame,
		0,             // Loop: 0 = no loop
		doneAction: 0
	);

	sig = sig * env * ampScale;
	sig = Pan2.ar(sig, pan);

	Out.ar(outBus, sig);
}).add;
