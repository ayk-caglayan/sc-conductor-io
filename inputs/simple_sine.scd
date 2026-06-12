// Template Input Routine
// Copy this file and modify for new input routine types
//
// @meta: (
//   name: \templateInput,
//   displayName: "Template Input",
//   category: \input,
//   parameters: [
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
//
// NAMING CONVENTION:
// - Filename: type_name.scd (e.g., buffer_record.scd for type \bufferRecord)
// - The main controller maps \bufferRecord -> "bufferrecord.scd" (lowercase)
//
// CONFIG FIELDS (from preset):
// - id: unique identifier (Symbol)
// - type: routine type (Symbol)
// - startBar: bar number to start (Integer, 1-indexed)
// - startBeat: beat number to start (Integer, 1-indexed)
// - durationBeats: how many beats to run (Integer)
// - ... additional type-specific parameters

{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats;
	var elapsedBeats, isActive, isComplete;
	var synth, oscDefName;
	var bar, beat, bpm;

	// Extract config
	inputID = config[\id];
	startBar = config[\startBar];
	startBeat = config[\startBeat];
	durationBeats = config[\durationBeats];

	// State
	elapsedBeats = 0;
	isActive = false;
	isComplete = false;
	synth = nil;

	// Unique OSCdef name to avoid conflicts
	oscDefName = ("metro_input_" ++ inputID).asSymbol;

	"[INPUT %] Registered: startBar=%, startBeat=%, duration=% beats".format(
		inputID, startBar, startBeat, durationBeats
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_input_reset_" ++ inputID).asSymbol, { |msg|
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"[INPUT %] Reset - freed active synth".format(inputID).postln;
		});
		isActive = false;
		isComplete = false;
		elapsedBeats = 0;
		"[INPUT %] Reset - ready to start again at %:%".format(inputID, startBar, startBeat).postln;
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
		if((bar == startBar) && (beat == startBeat) && isActive.not && isComplete.not, {
			isActive = true;
			elapsedBeats = 0;

			"[INPUT %] >>> STARTED at Bar %:%".format(inputID, bar, beat).postln;

			// =============================================================
			// YOUR START LOGIC HERE
			// =============================================================
			// Example: Allocate buffer, start recording synth
			//
			// var bufSize = durationBeats * (60.0 / bpm) * 1.2; // 20% margin
			// var buf = Buffer.alloc(server, server.sampleRate * bufSize, 1);
			// bufferDict[inputID] = buf;
			//
			// synth = Synth(\yourRecorderSynthDef, [
			//     \inBus, audioInputBus,
			//     \bufNum, buf
			// ], server);
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

				"[INPUT %] <<< STOPPED at Bar %:% (elapsed: % beats)".format(
					inputID, bar, beat, elapsedBeats
				).postln;

				// =============================================================
				// YOUR STOP LOGIC HERE
				// =============================================================
				// Example: Free the recording synth (buffer stays in dictionary)
				//
				// if(synth.notNil, {
				//     synth.free;
				//     synth = nil;
				// });
				//
				// "  Buffer % stored in bufferDict".format(inputID).postln;
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

/*
=============================================================================
IMPLEMENTATION CHECKLIST
=============================================================================

1. Copy this file and rename to match your type:
   \bufferRecord -> bufferrecord.scd
   \onsetRecord -> onsetrecord.scd

2. Add your type-specific parameters to the config extraction section

3. Implement START LOGIC:
   - Allocate any needed buffers
   - Store buffers in bufferDict[inputID]
   - Start any synths needed for recording/analysis

4. Implement STOP LOGIC:
   - Free any synths (buffers stay!)
   - Finalize any data processing
   - Store results in bufferDict if needed

5. Ensure cleanup frees synths but NOT buffers

=============================================================================
EXAMPLE: Buffer Recorder Implementation
=============================================================================

{ |bufferDict, config, server, audioInputBus|
    var inputID = config[\id];
    var startBar = config[\startBar];
    var startBeat = config[\startBeat];
    var durationBeats = config[\durationBeats];

    var elapsedBeats = 0, isActive = false, isComplete = false;
    var synth, buf;
    var oscDefName = ("metro_input_" ++ inputID).asSymbol;

    OSCdef(oscDefName, { |msg|
        var bar = msg[1].asInteger;
        var beat = msg[2].asInteger;
        var bpm = msg[3].asInteger;

        // START
        if((bar == startBar) && (beat == startBeat) && isActive.not && isComplete.not, {
            var bufSize = durationBeats * (60.0 / bpm) * 1.2;

            isActive = true;
            elapsedBeats = 0;

            buf = Buffer.alloc(server, server.sampleRate * bufSize, 1);
            bufferDict[inputID] = buf;

            synth = Synth(\bufferRecorder, [
                \inBus, audioInputBus,
                \bufNum, buf
            ], server);

            "[INPUT %] Started recording".format(inputID).postln;
        });

        // COUNT & STOP
        if(isActive, {
            elapsedBeats = elapsedBeats + 1;
            if(elapsedBeats >= durationBeats, {
                isActive = false;
                isComplete = true;

                if(synth.notNil, { synth.free; synth = nil; });
                "[INPUT %] Stopped recording, buffer stored".format(inputID).postln;
            });
        });
    }, '/metronome');

    // Cleanup
    {
        if(synth.notNil, { synth.free; });
        OSCdef(oscDefName).free;
    }
}

=============================================================================
*/
