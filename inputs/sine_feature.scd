// Sine Feature Input Routine
// Extracts spectral peaks using FluidSineFeature and accumulates them over
// the detection window. Stores the peak snapshot taken at stop time in
// bufferDict[id] as an Event:
//   (freqs: [f1, f2, ...], mags: [m1, m2, ...], numPeaks: n)
// Used with: \peakSonify output routine
//
// @meta: (
//   name: \sineFeature,
//   displayName: "Sine Feature",
//   category: \input,
//   requiredSynthdefs: ["sine_feature_analyzer.scd"],
//   parameters: [
//     (name: \numPeaks,  default: 10,  min: 1,    max: 20,   type: \int,   label: "Num Peaks (1-20)"),
//     (name: \threshold, default: -96, min: -120,  max: 0,    type: \float, label: "Detection Threshold (dB)")
//   ]
// )

{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats;
	var numPeaks, threshold;
	var elapsedBeats, isActive, isComplete;
	var synth, oscDefName, dataReceiverName;
	var outBus, targetGroup;
	var latestFreqs, latestMags;

	// Extract config
	inputID       = config[\id];
	startBar      = config[\startBar];
	startBeat     = config[\startBeat];
	durationBeats = config[\durationBeats];

	// SynthDef parameters
	numPeaks  = (config[\numPeaks]  ? 10).asInteger.clip(1, 20);
	threshold = config[\threshold]  ? -96;

	// FX chain routing
	outBus      = config[\outBus] ? 0;
	targetGroup = config[\group];

	// State
	elapsedBeats = 0;
	isActive     = false;
	isComplete   = false;
	synth        = nil;

	latestFreqs = Array.new(20);
	latestMags  = Array.new(20);

	oscDefName      = ("metro_input_"    ++ inputID).asSymbol;
	dataReceiverName = ("sinefeature_recv_" ++ inputID).asSymbol;

	"[INPUT %] Sine Feature registered: startBar=%, startBeat=%, duration=% beats, numPeaks=%".format(
		inputID, startBar, startBeat, durationBeats, numPeaks
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_input_reset_" ++ inputID).asSymbol, { |msg|
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"[INPUT %] Reset - freed sine feature synth".format(inputID).postln;
		});
		latestFreqs  = Array.new(20);
		latestMags   = Array.new(20);
		isActive     = false;
		isComplete   = false;
		elapsedBeats = 0;
		"[INPUT %] Reset - ready to start again at %:%".format(inputID, startBar, startBeat).postln;
	}, '/metronome/reset');

	// =========================================================================
	// DATA RECEIVER  (/sinefeature_data)
	// =========================================================================
	// Continuously updates the latest peak snapshot while active.
	// msg layout: [path, nodeID, replyID, inputID, f0, m0, f1, m1, ...]

	OSCdef(dataReceiverName, { |msg|
		var msgInputID = msg[3].asInteger;
		// inputID is used as a numeric tag in SendReply
		if(isActive && (msgInputID.asString == inputID.asString), {
			var rawFreqs = Array.new(20);
			var rawMags  = Array.new(20);
			20.do { |i|
				rawFreqs.add(msg[4 + (i * 2)].asFloat);
				rawMags.add(msg[5 + (i * 2)].asFloat);
			};
			// Keep only the requested number of peaks
			latestFreqs = rawFreqs.copyFromStart(numPeaks - 1);
			latestMags  = rawMags.copyFromStart(numPeaks - 1);
		});
	}, '/sinefeature_data');

	// =========================================================================
	// METRONOME LISTENER
	// =========================================================================

	OSCdef(oscDefName, { |msg|
		var bar, beat, bpm;
		bar  = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm  = msg[3].asInteger;

		// START
		if((bar == startBar) && (beat == startBeat) && isActive.not && isComplete.not, {
			isActive     = true;
			elapsedBeats = 0;
			latestFreqs  = Array.new(20);
			latestMags   = Array.new(20);

			"[INPUT %] >>> STARTED sine feature analysis at Bar %:%".format(inputID, bar, beat).postln;

			synth = Synth(\sineFeatureAnalyzer, [
				\inBus,     audioInputBus,
				\inputID,   inputID,
				\outBus,    outBus,
				\threshold, threshold
			], targetGroup ? server);

			"[INPUT %] Synth created".format(inputID).postln;
		});

		// COUNT & STOP
		if(isActive, {
			elapsedBeats = elapsedBeats + 1;

			if(elapsedBeats >= durationBeats, {
				isActive   = false;
				isComplete = true;

				"[INPUT %] <<< STOPPED sine feature at Bar %:% (elapsed: % beats)".format(
					inputID, bar, beat, elapsedBeats
				).postln;

				// Store the last captured snapshot in bufferDict
				bufferDict[inputID] = (
					freqs:    latestFreqs,
					mags:     latestMags,
					numPeaks: latestFreqs.size,
					type:     \sineFeature
				);

				"[INPUT %] Stored % peaks in bufferDict".format(inputID, latestFreqs.size).postln;

				if(synth.notNil, {
					synth.free;
					synth = nil;
				});
			});
		});
	}, '/metronome');

	// =========================================================================
	// CLEANUP FUNCTION
	// =========================================================================

	{
		"[INPUT %] Cleanup called".format(inputID).postln;

		if(synth.notNil, {
			synth.free;
			synth = nil;
			"  Freed synth".postln;
		});

		OSCdef(oscDefName).free;
		"  Freed OSCdef: %".format(oscDefName).postln;
		OSCdef(("metro_input_reset_" ++ inputID).asSymbol).free;
		"  Freed reset OSCdef: metro_input_reset_%".format(inputID).postln;
		OSCdef(dataReceiverName).free;
		"  Freed data receiver OSCdef: %".format(dataReceiverName).postln;
	}
}
