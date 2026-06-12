// Store Pitches Analyzer - Tracks pitch using FluidPitch and stores trajectory
// Sends pitch/confidence data via OSC for accumulation with duration tracking
// Used with: \storePitches input routine -> \pitchSonify output routine
//
// @meta: (
//   name: \storePitchesAnalyzer,
//   displayName: "Store Pitches Analyzer",
//   parameters: [
//     (name: \minFreq,    default: 80,   min: 20,   max: 500,  type: \float, label: "Min Freq (Hz)"),
//     (name: \maxFreq,    default: 2000, min: 200,  max: 8000, type: \float, label: "Max Freq (Hz)"),
//     (name: \updateRate, default: 30,   min: 1,    max: 60,   type: \float, label: "Update Rate (Hz)")
//   ]
// )

SynthDef(\storePitchesAnalyzer, {
	arg inBus = 0,
	    inputID = 0,
	    outBus = 0,
	    minFreq = 80,
	    maxFreq = 2000,
	    updateRate = 30;

	var sig, pitch, confidence, trig;

	sig = SoundIn.ar(inBus);

	#pitch, confidence = FluidPitch.kr(
		in: sig,
		minFreq: minFreq,
		maxFreq: maxFreq,
		algorithm: 1
	);

	trig = Impulse.kr(updateRate);

	SendReply.kr(trig, '/store_pitch_data', [inputID, pitch, confidence]);

	Out.ar(outBus, Silent.ar(2));
}).add;
