// Template Output Routine
// Copy this file and modify for new output routine types
//
// @meta: (
//   name: \templateOutput,
//   displayName: "Template Output",
//   category: \output,
//   requiredInputType: nil,
//   requiredSynthdefs: [],
//   parameters: [
//     (name: \duration, default: 4.0, min: 1, max: 64, type: \float, label: "Duration (beats)"),
//     (name: \ampScale, default: 0.7, min: 0, max: 1, type: \float, label: "Amplitude")
//   ]
// )
//
// OUTPUT ROUTINE CONTRACT:
// - Receives: bufferDict, config, server
// - Creates its own OSCdef for /metronome  (named metro_output_<id>)
// - Creates a second OSCdef for /metronome/reset (named metro_output_reset_<id>)
//   that clears hasTriggered so the routine re-arms on metronome reset
// - Reads from bufferDict using source ID
// - Triggers synths at specified bar/beat
// - Returns cleanup function that:
//   * Frees all synths created by this routine
//   * Frees BOTH OSCdefs (beat listener + reset listener)
//   * Does NOT free buffers (main controller handles that)
//
// NAMING CONVENTION:
// - Filename: type_name.scd (e.g., play_buffer.scd for type \playBuffer)
// - The main controller maps \playBuffer -> "playbuffer.scd" (lowercase)
//
// CONFIG FIELDS (from preset):
// - id: unique identifier (Symbol)
// - type: routine type (Symbol)
// - source: ID of input routine to read buffer from (Symbol)
// - bar: bar number to trigger (Integer, 1-indexed)
// - beat: beat number to trigger (Integer, 1-indexed)
// - duration: playback duration in beats (Float)
// - ... additional type-specific parameters (ampScale, rate, etc.)

{ |bufferDict, config, server|
	var outputID, sourceID, triggerBar, triggerBeat, duration;
	var hasTriggered, synth, oscDefName;
	var bar, beat, bpm;

	// Extract config
	outputID = config[\id];
	sourceID = config[\source];
	triggerBar = config[\bar];
	triggerBeat = config[\beat];
	duration = config[\duration] ? 4.0;

	// State
	hasTriggered = false;
	synth = nil;

	// Unique OSCdef name to avoid conflicts
	oscDefName = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Registered: trigger=%:%, source=%, duration=% beats".format(
		outputID, triggerBar, triggerBeat, sourceID, duration
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================
	// Re-arms the routine when metronome.scd sends an explicit reset.
	// Named metro_output_reset_<id> so cleanup can free it independently.

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
		// Optionally free any currently playing synth on hard reset
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"[OUTPUT %] Reset - freed active synth".format(outputID).postln;
		});
		hasTriggered = false;
		"[OUTPUT %] Reset - ready to trigger again at %:%".format(outputID, triggerBar, triggerBeat).postln;
	}, '/metronome/reset');

	// =========================================================================
	// METRONOME LISTENER
	// =========================================================================

	OSCdef(oscDefName, { |msg|
		bar = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm = msg[3].asInteger;

		// -----------------------------------------------------------------
		// TRIGGER CONDITION: At triggerBar:triggerBeat, not already triggered
		// -----------------------------------------------------------------
		if((bar.asInteger == triggerBar.asInteger) && (beat.asInteger == triggerBeat.asInteger) && hasTriggered.not, {
			var sourceData, beatDuration, synthDuration;

			hasTriggered = true;
			beatDuration = 60.0 / bpm;
			synthDuration = duration * beatDuration;

			"[OUTPUT %] *** TRIGGERED at Bar %:%".format(outputID, bar, beat).postln;

			// Get source data from buffer dictionary
			sourceData = bufferDict[sourceID];

			if(sourceData.isNil, {
				"[OUTPUT %] ERROR: Source % not found in bufferDict!".format(
					outputID, sourceID
				).postln;
			}, {
				// =============================================================
				// YOUR TRIGGER LOGIC HERE
				// =============================================================
				// Example: Play buffer
				//
				// if(sourceData.isKindOf(Buffer), {
				//     synth = Synth(\yourPlayerSynthDef, [
				//         \bufNum, sourceData,
				//         \rate, config[\rate] ? 1.0,
				//         \amp, config[\ampScale] ? 0.7
				//     ], server);
				//
				//     "  Playing buffer % for % seconds".format(
				//         sourceID, synthDuration.round(0.01)
				//     ).postln;
				// });
				//
				// For complex source data (e.g., onset slicing):
				// if(sourceData.isKindOf(Event), {
				//     var buf = sourceData[\buffer];
				//     var indices = sourceData[\indices];
				//     // ... use both buffers
				// });
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
		"[OUTPUT %] Cleanup called".format(outputID).postln;

		// Free synth if still running
		if(synth.notNil, {
			synth.free;
			synth = nil;
			"  Freed synth".postln;
		});

		// Free the beat listener and the reset listener
		OSCdef(oscDefName).free;
		"  Freed OSCdef: %".format(oscDefName).postln;
		OSCdef(("metro_output_reset_" ++ outputID).asSymbol).free;
		"  Freed reset OSCdef: metro_output_reset_%".format(outputID).postln;

		// NOTE: Do NOT free buffers here - main controller handles that
	}
}

/*
=============================================================================
IMPLEMENTATION CHECKLIST
=============================================================================

1. Copy this file and rename to match your type:
   \playBuffer -> playbuffer.scd
   \onsetSlice -> onsetslice.scd

2. Add your type-specific parameters to the config extraction section
   (e.g., rate, ampScale, loop, etc.)

3. Implement TRIGGER LOGIC:
   - Get source data from bufferDict[sourceID]
   - Check data type (Buffer vs Event for complex data)
   - Create and start playback synth(s)

4. Handle synth lifetime:
   - Some synths free themselves (doneAction: 2)
   - Others need manual release (gate-controlled)
   - Store synth reference if manual release needed

5. Ensure cleanup frees synths but NOT buffers

=============================================================================
EXAMPLE: Buffer Player Implementation
=============================================================================

{ |bufferDict, config, server|
    var outputID = config[\id];
    var sourceID = config[\source];
    var triggerBar = config[\bar];
    var triggerBeat = config[\beat];
    var rate = config[\rate] ? 1.0;
    var ampScale = config[\ampScale] ? 0.7;
    var loop = config[\loop] ? false;

    var hasTriggered = false;
    var synth;
    var oscDefName = ("metro_output_" ++ outputID).asSymbol;

    OSCdef(oscDefName, { |msg|
        var bar = msg[1].asInteger;
        var beat = msg[2].asInteger;
        var bpm = msg[3].asInteger;

        // RESET when metronome goes back
        if(hasTriggered && (bar < triggerBar), {
            hasTriggered = false;
        });

        if((bar == triggerBar) && (beat == triggerBeat) && hasTriggered.not, {
            var buf = bufferDict[sourceID];

            hasTriggered = true;

            if(buf.isKindOf(Buffer), {
                synth = Synth(\bufferPlayer, [
                    \bufNum, buf,
                    \rate, rate,
                    \amp, ampScale,
                    \loop, loop.asInteger
                ], server);

                "[OUTPUT %] Playing buffer %".format(outputID, sourceID).postln;
            }, {
                "[OUTPUT %] Source % is not a Buffer".format(outputID, sourceID).postln;
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
EXAMPLE: Gate-Controlled Synth (manual release after duration)
=============================================================================

{ |bufferDict, config, server|
    var outputID = config[\id];
    var sourceID = config[\source];
    var triggerBar = config[\bar];
    var triggerBeat = config[\beat];
    var duration = config[\duration] ? 4.0;

    var hasTriggered = false;
    var synths = List.new;
    var oscDefName = ("metro_output_" ++ outputID).asSymbol;

    OSCdef(oscDefName, { |msg|
        var bar = msg[1].asInteger;
        var beat = msg[2].asInteger;
        var bpm = msg[3].asInteger;

        // RESET when metronome goes back
        if(hasTriggered && (bar < triggerBar), {
            hasTriggered = false;
        });

        if((bar == triggerBar) && (beat == triggerBeat) && hasTriggered.not, {
            var sourceData = bufferDict[sourceID];
            var beatDuration = 60.0 / bpm;
            var synthDuration = duration * beatDuration;

            hasTriggered = true;

            if(sourceData.notNil, {
                // Create gate-controlled synth(s)
                var synth = Synth(\yourGatedSynth, [
                    \gate, 1,
                    // ... other params
                ], server);
                synths.add(synth);

                // Schedule gate release after duration
                {
                    synths.do { |s| s.set(\gate, 0); };
                }.defer(synthDuration);

                "[OUTPUT %] Started, will release in % sec".format(
                    outputID, synthDuration.round(0.01)
                ).postln;
            });
        });
    }, '/metronome');

    // Cleanup
    {
        synths.do { |s| s.free; };
        synths.clear;
        OSCdef(oscDefName).free;
    }
}

=============================================================================
*/
