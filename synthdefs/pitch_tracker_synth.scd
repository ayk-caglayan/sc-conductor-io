// Pitch Tracker Analyzer SynthDef
// Uses FluidPitch for real-time pitch detection and sonifies with sine wave
//
// Args:
//   inBus: audio input bus
//   inputID: identifier for this input
//   minFreq: minimum frequency for pitch detection (Hz)
//   maxFreq: maximum frequency for pitch detection (Hz)
//   ampScale: amplitude scaling factor
//   confidenceThreshold: minimum confidence level for sonification
//
// @meta: (
//   name: \pitchTrackerAnalyzer,
//   displayName: "Pitch Tracker",
//   parameters: [
//     (name: \minFreq,              default: 80,   min: 20,   max: 500,  type: \float, label: "Min Freq (Hz)"),
//     (name: \maxFreq,              default: 2000, min: 200,  max: 8000, type: \float, label: "Max Freq (Hz)"),
//     (name: \ampScale,             default: 0.3,  min: 0.0,  max: 2.0,  type: \float, label: "Amplitude Scale"),
//     (name: \confidenceThreshold,  default: 0.7,  min: 0.0,  max: 1.0,  type: \float, label: "Confidence Threshold")
//   ]
// )

SynthDef(\pitchTrackerAnalyzer, { |inBus = 0, inputID = 0, minFreq = 80, maxFreq = 2000, ampScale = 0.3, confidenceThreshold = 0.7|
	var sig, pitch, confidence, trig, synthSig, env;

	// Read input audio
	sig = SoundIn.ar(inBus);

	// Detect pitch using FluidPitch
	#pitch, confidence = FluidPitch.kr(
		in: sig,
		minFreq: minFreq,
		maxFreq: maxFreq,
		algorithm: 1
	);

	// Gate confidence at threshold
	confidence = (confidence > confidenceThreshold).asInteger.asFloat * confidence;

	// Smooth confidence changes for amplitude envelope
	env = Lag.kr(confidence, 0.1);

	// Sonify with sine wave at detected pitch
	synthSig = SinOsc.ar(pitch) * env * ampScale;

	// Output to stereo
	Out.ar(0, synthSig ! 2);

	// Send pitch data for monitoring (optional)
	trig = Impulse.kr(5); // 5 Hz update rate
	SendReply.kr(trig, '/pitch_data', [inputID, pitch, confidence]);

}).add;
