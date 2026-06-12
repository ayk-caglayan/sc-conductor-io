// Live Pitches Input Routine
// Tracks incoming audio pitch in real-time using FluidPitch and sonifies
// it with a sine wave. No output trigger needed — sound is produced directly
// during the detection window.
//
// @meta: (
//   name: \livePitches,
//   displayName: "Live Pitches",
//   category: \input,
//   requiredSynthdefs: ["live_pitches_analyzer.scd"],
//   parameters: [
//     (name: \minFreq,             default: 80,   min: 20,   max: 500,  type: \float, label: "Min Freq (Hz)"),
//     (name: \maxFreq,             default: 2000, min: 200,  max: 8000, type: \float, label: "Max Freq (Hz)"),
//     (name: \ampScale,            default: 0.3,  min: 0.0,  max: 1.0,  type: \float, label: "Amp Scale"),
//     (name: \confidenceThreshold, default: 0.7,  min: 0.0,  max: 1.0,  type: \float, label: "Confidence Threshold"),
//     (name: \lagTime,             default: 0.1,  min: 0.01, max: 1.0,  type: \float, label: "Confidence Lag Time (s)")
//   ]
// )

{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats;
	var minFreq, maxFreq, ampScale, confidenceThreshold, lagTime;
	var elapsedBeats, isActive, isComplete;
	var synth, oscDefName;
	var outBus, targetGroup;

	// Extract config
	inputID       = config[\id];
	startBar      = config[\startBar];
	startBeat     = config[\startBeat];
	durationBeats = config[\durationBeats];

	// SynthDef parameters
	minFreq             = config[\minFreq]             ? 80;
	maxFreq             = config[\maxFreq]             ? 2000;
	ampScale            = config[\ampScale]            ? 0.3;
	confidenceThreshold = config[\confidenceThreshold] ? 0.7;
	lagTime             = config[\lagTime]             ? 0.1;

	// FX chain routing (injected by routines.scd when fxChains configured)
	outBus      = config[\outBus] ? 0;
	targetGroup = config[\group];

	// State
	elapsedBeats = 0;
	isActive     = false;
	isComplete   = false;
	synth        = nil;

	oscDefName = ("metro_input_" ++ inputID).asSymbol;

	"[INPUT %] Live Pitches registered: startBar=%, startBeat=%, duration=% beats".format(
		inputID, startBar, startBeat, durationBeats
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_input_reset_" ++ inputID).asSymbol, { |msg|
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"[INPUT %] Reset - freed live pitches synth".format(inputID).postln;
		});
		isActive   = false;
		isComplete = false;
		elapsedBeats = 0;
		"[INPUT %] Reset - ready to start again at %:%".format(inputID, startBar, startBeat).postln;
	}, '/metronome/reset');

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

			"[INPUT %] >>> STARTED live pitch tracking at Bar %:%".format(inputID, bar, beat).postln;

			synth = Synth(\livePitchesAnalyzer, [
				\inBus,               audioInputBus,
				\inputID,             inputID,
				\outBus,              outBus,
				\minFreq,             minFreq,
				\maxFreq,             maxFreq,
				\ampScale,            ampScale,
				\confidenceThreshold, confidenceThreshold,
				\lagTime,             lagTime
			], targetGroup ? server);

			"[INPUT %] Synth created".format(inputID).postln;
		});

		// COUNT & STOP
		if(isActive, {
			elapsedBeats = elapsedBeats + 1;

			if(elapsedBeats >= durationBeats, {
				isActive   = false;
				isComplete = true;

				"[INPUT %] <<< STOPPED live pitches at Bar %:% (elapsed: % beats)".format(
					inputID, bar, beat, elapsedBeats
				).postln;

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
	}
}
