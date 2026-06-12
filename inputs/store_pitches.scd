// Store Pitches Input Routine
// Tracks pitch using FluidPitch and accumulates the trajectory over the
// detection window. Stores the pitch list in bufferDict[id] as an Event:
//   (pitches: [f1, f2, ...], confidences: [c1, c2, ...], type: \storePitches)
// Used with: \pitchSonify output routine
//
// @meta: (
//   name: \storePitches,
//   displayName: "Store Pitches",
//   category: \input,
//   requiredSynthdefs: ["store_pitches_analyzer.scd"],
//   parameters: [
//     (name: \minFreq,             default: 80,   min: 20,   max: 500,  type: \float, label: "Min Freq (Hz)"),
//     (name: \maxFreq,             default: 2000, min: 200,  max: 8000, type: \float, label: "Max Freq (Hz)"),
//     (name: \updateRate,          default: 30,   min: 1,    max: 60,   type: \float, label: "Update Rate (Hz)"),
//     (name: \confidenceThreshold, default: 0.7,  min: 0.0,  max: 1.0,  type: \float, label: "Confidence Threshold")
//   ]
// )

{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats;
	var minFreq, maxFreq, updateRate, confidenceThreshold;
	var elapsedBeats, isActive, isComplete;
	var synth, oscDefName, dataReceiverName;
	var outBus, targetGroup;
	var pitchList, confidenceList;

	// Extract config
	inputID       = config[\id];
	startBar      = config[\startBar];
	startBeat     = config[\startBeat];
	durationBeats = config[\durationBeats];

	// SynthDef parameters
	minFreq             = config[\minFreq]             ? 80;
	maxFreq             = config[\maxFreq]             ? 2000;
	updateRate          = config[\updateRate]          ? 30;
	confidenceThreshold = config[\confidenceThreshold] ? 0.7;

	// FX chain routing
	outBus      = config[\outBus] ? 0;
	targetGroup = config[\group];

	// State
	elapsedBeats = 0;
	isActive     = false;
	isComplete   = false;
	synth        = nil;

	pitchList      = List.new;
	confidenceList = List.new;

	oscDefName       = ("metro_input_"       ++ inputID).asSymbol;
	dataReceiverName = ("store_pitch_recv_"  ++ inputID).asSymbol;

	"[INPUT %] Store Pitches registered: startBar=%, startBeat=%, duration=% beats, updateRate=%Hz".format(
		inputID, startBar, startBeat, durationBeats, updateRate
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_input_reset_" ++ inputID).asSymbol, { |msg|
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"[INPUT %] Reset - freed store pitches synth".format(inputID).postln;
		});
		pitchList.clear;
		confidenceList.clear;
		isActive     = false;
		isComplete   = false;
		elapsedBeats = 0;
		"[INPUT %] Reset - ready to start again at %:%".format(inputID, startBar, startBeat).postln;
	}, '/metronome/reset');

	// =========================================================================
	// DATA RECEIVER  (/store_pitch_data)
	// =========================================================================
	// msg layout: [path, nodeID, replyID, inputID, pitch, confidence]

	OSCdef(dataReceiverName, { |msg|
		var msgInputID = msg[3];
		var pitch      = msg[4].asFloat;
		var conf       = msg[5].asFloat;

		if(isActive && (msgInputID.asString == inputID.asString), {
			if(conf >= confidenceThreshold, {
				pitchList.add(pitch);
				confidenceList.add(conf);
			});
		});
	}, '/store_pitch_data');

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
			pitchList.clear;
			confidenceList.clear;

			"[INPUT %] >>> STARTED pitch storage at Bar %:%".format(inputID, bar, beat).postln;

			synth = Synth(\storePitchesAnalyzer, [
				\inBus,      audioInputBus,
				\inputID,    inputID,
				\outBus,     outBus,
				\minFreq,    minFreq,
				\maxFreq,    maxFreq,
				\updateRate, updateRate
			], targetGroup ? server);

			"[INPUT %] Synth created".format(inputID).postln;
		});

		// COUNT & STOP
		if(isActive, {
			elapsedBeats = elapsedBeats + 1;

			if(elapsedBeats >= durationBeats, {
				isActive   = false;
				isComplete = true;

				"[INPUT %] <<< STOPPED pitch storage at Bar %:% (elapsed: % beats, stored % pitches)".format(
					inputID, bar, beat, elapsedBeats, pitchList.size
				).postln;

				// Store accumulated pitch trajectory in bufferDict
				bufferDict[inputID] = (
					pitches:     pitchList.asArray,
					confidences: confidenceList.asArray,
					type:        \storePitches
				);

				"[INPUT %] Stored % pitches in bufferDict".format(inputID, pitchList.size).postln;

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
