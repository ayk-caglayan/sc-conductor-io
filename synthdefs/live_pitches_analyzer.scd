// Live Pitches Analyzer - Tracks and sonifies pitch in real-time using FluidPitch
// Outputs sine tone following detected pitch with confidence-based amplitude
// No output trigger needed - sonifies automatically during detection window
//
// @meta: (
//   name: \livePitchesAnalyzer,
//   displayName: "Live Pitches Analyzer",
//   parameters: [
//     (name: \minFreq,             default: 80,   min: 20,   max: 500,  type: \float, label: "Min Freq (Hz)"),
//     (name: \maxFreq,             default: 2000, min: 200,  max: 8000, type: \float, label: "Max Freq (Hz)"),
//     (name: \ampScale,            default: 0.3,  min: 0.0,  max: 1.0,  type: \float, label: "Amp Scale"),
//     (name: \confidenceThreshold, default: 0.7,  min: 0.0,  max: 1.0,  type: \float, label: "Confidence Threshold"),
//     (name: \lagTime,             default: 0.1,  min: 0.01, max: 1.0,  type: \float, label: "Confidence Lag Time (s)")
//   ]
// )

SynthDef(\livePitchesAnalyzer, {
	arg inBus = 0,
	    inputID = 0,
	    outBus = 0,
	    minFreq = 80,
	    maxFreq = 2000,
	    ampScale = 0.3,
	    confidenceThreshold = 0.7,
	    lagTime = 0.1;

	var sig, pitch, confidence, trig, synthSig, env;

	sig = SoundIn.ar(inBus);

	#pitch, confidence = FluidPitch.kr(
		in: sig,
		minFreq: minFreq,
		maxFreq: maxFreq,
		algorithm: 1
	);

	// Gate confidence at threshold, then smooth amplitude changes
	env = Lag.kr((confidence > confidenceThreshold).asInteger.asFloat * confidence, lagTime);

	// Sonify the detected pitch in real-time
	synthSig = SinOsc.ar(pitch) * env * ampScale;

	Out.ar(outBus, synthSig ! 2);

	// Send pitch data for monitoring
	trig = Impulse.kr(5);
	SendReply.kr(trig, '/live_pitch_data', [inputID, pitch, confidence]);
}).add;
