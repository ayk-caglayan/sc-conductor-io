// Buffer Record Input Routine
// Records audio from hardware input into a buffer
//
// @meta: (
//   name: \bufferRecordInput,
//   displayName: "Buffer Record",
//   category: \input,
//   requiredSynthdefs: ["buffer_recorder_synth.scd"],
//   parameters: [
//     (name: \amp, default: 1.0, min: 0, max: 2, type: \float, label: "Input Gain"),
//     (name: \bufferMargin, default: 1.2, min: 1.0, max: 2.0, type: \float, label: "Buffer Margin")
//   ]
// )
//
// INPUT ROUTINE CONTRACT:
// - Receives: bufferDict, config, server, audioInputBus
// - Creates its own OSCdef for /metronome
// - Computes beat-based timing from bar/beat info
// - Writes to bufferDict with its ID as key
// - Returns cleanup function that:
//   * Frees all synths created by this routine
//   * Frees the OSCdef
//   * Does NOT free buffers (main controller handles that)

{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats;
	var amp, bufferMargin;
	var elapsedBeats, isActive, isComplete;
	var synth, buf, oscDefName;
	var bar, beat, bpm;

	// Extract config
	inputID = config[\id];
	startBar = config[\startBar];
	startBeat = config[\startBeat];
	durationBeats = config[\durationBeats];
	amp = config[\amp] ? 1.0;
	bufferMargin = config[\bufferMargin] ? 1.2;

	// State
	elapsedBeats = 0;
	isActive = false;
	isComplete = false;
	synth = nil;
	buf = nil;

	// Unique OSCdef name to avoid conflicts
	oscDefName = ("metro_input_" ++ inputID).asSymbol;

	"[INPUT %] Buffer Record registered: startBar=%, startBeat=%, duration=% beats".format(
		inputID, startBar, startBeat, durationBeats
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================
	// Re-arms the routine when metronome.scd sends an explicit reset.
	// A second OSCdef (metro_input_reset_<id>) is used so the beat listener
	// and the reset listener can be freed independently during cleanup.

	OSCdef(("metro_input_reset_" ++ inputID).asSymbol, { |msg|
		// Free any in-progress recording synth before clearing state
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"[INPUT %] Reset - freed in-progress recording synth".format(inputID).postln;
		});
		isActive = false;
		isComplete = false;
		elapsedBeats = 0;
		"[INPUT %] Reset - ready to record again at %:%".format(inputID, startBar, startBeat).postln;
	}, '/metronome/reset');

	// =========================================================================
	// METRONOME LISTENER
	// =========================================================================

	OSCdef(oscDefName, { |msg|
		var wasActive;
		bar = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm = msg[3].asInteger;

		// Snapshot active state before the start block may change it.
		// This ensures the beat counter only ticks on beats *after* the
		// start beat (i.e., the stop fires at the onset of beat N+1,
		// giving the full duration of beat N before stopping).
		wasActive = isActive;

		// -----------------------------------------------------------------
		// START CONDITION: At startBar:startBeat, not already active
		// -----------------------------------------------------------------
		if((bar.asInteger == startBar.asInteger) && (beat.asInteger == startBeat.asInteger) && isActive.not && isComplete.not, {
			// Convert beats to seconds
			var beatDuration = 60.0 / bpm;
			var durationSec = durationBeats * beatDuration;
			var bufSize = durationSec * bufferMargin;

			isActive = true;
			elapsedBeats = 0;

			"[INPUT %] >>> STARTED recording at Bar %:% (duration: % beats = % sec at % BPM)".format(
				inputID, bar, beat, durationBeats, durationSec.round(0.01), bpm
			).postln;

			// Allocate buffer and store in bufferDict after allocation completes
			buf = Buffer.alloc(server, server.sampleRate * bufSize, 1, { |allocatedBuf|
				"[INPUT %] Buffer allocated: bufnum=%, % frames (% sec)".format(
					inputID, allocatedBuf.bufnum, (server.sampleRate * bufSize).round, bufSize.round(0.01)
				).postln;

				// Store buffer in dictionary after allocation is complete
				bufferDict[inputID] = allocatedBuf;

				// Start recording synth after buffer is allocated
				synth = Synth(\bufferRecordInputSynth, [
					\inBus, audioInputBus,
					\bufNum, allocatedBuf.bufnum,
					\amp, amp
				], server);

				"[INPUT %] Recording synth started (bufnum=%)".format(inputID, allocatedBuf.bufnum).postln;
			});
		});

		// -----------------------------------------------------------------
		// ACTIVE: Count beats and check for completion
		// Only count if we were already active before this tick (wasActive).
		// This skips the start beat itself so durationBeats=5 means the
		// recording runs through the end of beat 5 (stops at beat 6 onset).
		// -----------------------------------------------------------------
		if(wasActive, {
			elapsedBeats = elapsedBeats + 1;

			// Check if duration reached
			if(elapsedBeats >= durationBeats, {
				isActive = false;
				isComplete = true;

				"[INPUT %] <<< STOPPED recording at Bar %:% (elapsed: % beats)".format(
					inputID, bar, beat, elapsedBeats
				).postln;

				// Free the recording synth (buffer stays in dictionary)
				if(synth.notNil, {
					synth.free;
					synth = nil;
					"[INPUT %] Recording synth freed, buffer stored as '%'".format(inputID, inputID).postln;
				});
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
