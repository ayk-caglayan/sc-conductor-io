// Pitch Tracker Input Routine
// Tracks incoming audio pitch using FluidPitch and sonifies it with a sine wave
// Stores detected pitches in bufferDict for use by output routines
//
// @meta: (
//   name: \pitchTracker,
//   displayName: "Pitch Tracker",
//   category: \input,
//   requiredSynthdefs: ["pitch_tracker_synth.scd"],
//   parameters: [
//     (name: \minFreq, default: 80, min: 20, max: 500, type: \float, label: "Min Freq (Hz)"),
//     (name: \maxFreq, default: 2000, min: 500, max: 5000, type: \float, label: "Max Freq (Hz)"),
//     (name: \ampScale, default: 0.3, min: 0, max: 1, type: \float, label: "Amplitude"),
//     (name: \confidenceThreshold, default: 0.7, min: 0, max: 1, type: \float, label: "Confidence Threshold")
//   ]
// )

{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats;
	var minFreq, maxFreq, ampScale, confidenceThreshold;
	var elapsedBeats, isActive, isComplete;
	var synth, oscDefName;
	var bar, beat, bpm;

	// Extract config
	inputID = config[\id];
	startBar = config[\startBar];
	startBeat = config[\startBeat];
	durationBeats = config[\durationBeats];
	minFreq = config[\minFreq] ? 80;
	maxFreq = config[\maxFreq] ? 2000;
	ampScale = config[\ampScale] ? 0.3;
	confidenceThreshold = config[\confidenceThreshold] ? 0.7;

	// State
	elapsedBeats = 0;
	isActive = false;
	isComplete = false;
	synth = nil;

	// Unique OSCdef name to avoid conflicts
	oscDefName = ("metro_input_" ++ inputID).asSymbol;

	"[INPUT %] Pitch Tracker registered: startBar=%, startBeat=%, duration=% beats".format(
		inputID, startBar, startBeat, durationBeats
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_input_reset_" ++ inputID).asSymbol, { |msg|
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"[INPUT %] Reset - freed active pitch tracker synth".format(inputID).postln;
		});
		isActive = false;
		isComplete = false;
		elapsedBeats = 0;
		"[INPUT %] Reset - ready to track again at %:%".format(inputID, startBar, startBeat).postln;
	}, '/metronome/reset');

	// =========================================================================
	// METRONOME LISTENER
	// =========================================================================

	OSCdef(oscDefName, { |msg|
		bar = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm = msg[3].asInteger;

		// -----------------------------------------------------------------
		// START CONDITION: At startBar:startBeat, not already active
		// -----------------------------------------------------------------
		if((bar.asInteger == startBar.asInteger) && (beat.asInteger == startBeat.asInteger) && isActive.not && isComplete.not, {
			isActive = true;
			elapsedBeats = 0;

			"[INPUT %] >>> STARTED pitch tracking at Bar %:%".format(inputID, bar, beat).postln;

			// =============================================================
			// START: Create pitch tracking synth
			// =============================================================
			synth = Synth(\pitchTrackerAnalyzer, [
				\inBus, audioInputBus,
				\inputID, inputID,
				\minFreq, minFreq,
				\maxFreq, maxFreq,
				\ampScale, ampScale,
				\confidenceThreshold, confidenceThreshold
			], server);
			
			"[INPUT %] Synth created for pitch tracking".format(inputID).postln;
			// =============================================================
		});

		// -----------------------------------------------------------------
		// ACTIVE: Count beats and check for completion
		// -----------------------------------------------------------------
		if(isActive, {
			elapsedBeats = elapsedBeats + 1;

			// Check if duration reached
			if(elapsedBeats >= durationBeats, {
				isActive = false;
				isComplete = true;

				"[INPUT %] <<< STOPPED pitch tracking at Bar %:% (elapsed: % beats)".format(
					inputID, bar, beat, elapsedBeats
				).postln;

				// =============================================================
				// STOP: Free the synth (store results if needed)
				// =============================================================
				if(synth.notNil, {
					synth.free;
					synth = nil;
				});

				"[INPUT %] Pitch tracking complete".format(inputID).postln;
				// =============================================================
			});
		});
	}, '/metronome');

	// =========================================================================
	// CLEANUP FUNCTION
	// =========================================================================
	// This function is called by the main controller during ~cleanup
	// It should free synths and OSCdefs, but NOT buffers

	{
		"[INPUT %] Cleanup called".format(inputID).postln;

		// Free synth if still running
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"  Freed synth".postln;
		});

		// Free the beat listener and the reset listener
		OSCdef(oscDefName).free;
		"  Freed OSCdef: %".format(oscDefName).postln;
		OSCdef(("metro_input_reset_" ++ inputID).asSymbol).free;
		"  Freed reset OSCdef: metro_input_reset_%".format(inputID).postln;

		// NOTE: Do NOT free buffers here - main controller handles that
	}
}
