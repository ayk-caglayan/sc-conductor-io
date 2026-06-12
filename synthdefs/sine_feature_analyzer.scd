// Sine Feature Analyzer - Extracts spectral peaks using FluidSineFeature
// Sends peak frequency/magnitude data via OSC for accumulation
// Used with: \sineFeature input routine -> \peakSonify output routine
//
// Note: FluidSineFeature requires numPeaks and windowSize to be compile-time
// constants. Therefore: always analyzes 20 peaks (maximum), sends all via OSC;
// the routine receiver filters to the requested numPeaks (1-20).
//
// @meta: (
//   name: \sineFeatureAnalyzer,
//   displayName: "Sine Feature Analyzer",
//   parameters: [
//     (name: \threshold, default: -96, min: -120, max: 0, type: \float, label: "Detection Threshold (dB)")
//   ]
// )

SynthDef(\sineFeatureAnalyzer, {
	arg inBus = 0,
	    inputID = 0,
	    outBus = 0,
	    threshold = -96;

	var sig, freqs, mags, trig, data;
	var maxPeaks = 20;

	sig = SoundIn.ar(inBus);

	#freqs, mags = FluidSineFeature.kr(
		in: sig,
		numPeaks: maxPeaks,
		detectionThreshold: threshold,
		order: 0,
		freqUnit: 0,
		magUnit: 0,
		windowSize: 1024,
		hopSize: -1,
		fftSize: -1,
		maxFFTSize: -1
	);

	trig = Impulse.kr(SampleRate.ir / 512);

	// Send all peaks; routine receiver uses only what it needs
	data = Array.fill(maxPeaks * 2, 0);
	maxPeaks.do { |i|
		data[i * 2] = freqs[i];
		data[(i * 2) + 1] = mags[i];
	};

	SendReply.kr(trig, '/sinefeature_data', [inputID] ++ data);

	Out.ar(outBus, Silent.ar(2));
}).add;
