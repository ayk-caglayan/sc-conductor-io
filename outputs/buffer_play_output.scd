// Buffer Player Output Routine
// Plays back audio buffers with rate/pan control when triggered
//
// @meta: (
//   name: \bufferPlayOutput,
//   displayName: "Buffer Player Output",
//   category: \output,
//   requiredInputType: \bufferRecord,
//   requiredSynthdefs: ["buffer_player_synth.scd"],
//   parameters: [
//     (name: \duration, default: 4.0, min: 0.5, max: 64, type: \float, label: "Duration (beats)"),
//     (name: \ampScale, default: 0.5, min: 0, max: 1, type: \float, label: "Amplitude"),
//     (name: \bufRate, default: 1.0, min: 0.1, max: 4.0, type: \float, label: "Playback Rate"),
//     (name: \pan, default: 0, min: -1, max: 1, type: \float, label: "Pan")
//   ]
// )

{ |bufferDict, config, server|
	var outputID, sourceID, triggerBar, triggerBeat, duration;
	var ampScale, bufRate, pan, outBus, targetGroup;
	var hasTriggered, synth, oscDefName;

	// Extract config
	outputID = config[\id];
	sourceID = config[\source];
	triggerBar = config[\bar];
	triggerBeat = config[\beat];
	duration = config[\duration] ? 4.0;
	ampScale = config[\ampScale] ? 0.5;
	bufRate = config[\bufRate] ? 1.0;
	pan = config[\pan] ? 0;
	outBus = config[\outBus] ? 0;
	targetGroup = config[\group];

	// State
	hasTriggered = false;
	synth = nil;

	// Unique OSCdef name to avoid conflicts
	oscDefName = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Buffer Player registered: trigger=%:%, source=%, rate=%, amp=%".format(
		outputID, triggerBar, triggerBeat, sourceID, bufRate, ampScale
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
		// Optionally stop any currently playing synth on hard reset
		if(synth.notNil, {
			try { synth.free; };
			synth = nil;
			"[OUTPUT %] Reset - stopped in-progress playback".format(outputID).postln;
		});
		hasTriggered = false;
		"[OUTPUT %] Reset - ready to trigger again at %:%".format(outputID, triggerBar, triggerBeat).postln;
	}, '/metronome/reset');

	// =========================================================================
	// METRONOME LISTENER
	// =========================================================================

	OSCdef(oscDefName, { |msg|
		var bar, beat, bpm;

		bar = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm = msg[3].asInteger;

		// Trigger at specified bar:beat
		if((bar.asInteger == triggerBar.asInteger) && (beat.asInteger == triggerBeat.asInteger) && hasTriggered.not, {
			var sourceData, durSec;

			hasTriggered = true;

			// Convert duration from beats to seconds using BPM
			// beats / (beats per minute) * 60 = seconds
			durSec = (duration / bpm) * 60;

			"[OUTPUT %] *** TRIGGERED at Bar %:% (duration: % beats = % sec at % BPM)".format(
				outputID, bar, beat, duration, durSec.round(0.01), bpm
			).postln;

			// Get source data from buffer dictionary
			sourceData = bufferDict[sourceID];

			if(sourceData.isNil, {
				"[OUTPUT %] ERROR: Source % not found in bufferDict!".format(
					outputID, sourceID
				).postln;
			}, {
				// Check if source is a Buffer directly or an Event containing a buffer
				var buf;

				if(sourceData.isKindOf(Buffer), {
					buf = sourceData;
				}, {
					if(sourceData.isKindOf(Event) && sourceData[\buffer].notNil, {
						buf = sourceData[\buffer];
					});
				});

				if(buf.notNil && buf.isKindOf(Buffer), {
				synth = Synth(\bufferPlayOutputSynth, [
					\bufNum, buf.bufnum,
					\outBus, outBus,
					\bufRate, bufRate,
					\amp, ampScale,
					\pan, pan,
					\startPos, 0,
					\durSec, durSec
				], targetGroup ? server);

					"  Playing buffer % (bufnum=%) at rate %x, amp=%, duration=% sec".format(
						sourceID, buf.bufnum, bufRate, ampScale, durSec.round(0.01)
					).postln;
				}, {
					"[OUTPUT %] ERROR: Source % is not a Buffer (got %)".format(
						outputID, sourceID, sourceData.class
					).postln;
				});
			});
		});
	}, '/metronome');

	// =========================================================================
	// CLEANUP FUNCTION
	// =========================================================================

	{
		"[OUTPUT %] Cleanup called".format(outputID).postln;

		// Free synth if still running (use try to avoid "node not found" errors)
		if(synth.notNil, {
			try { synth.free; };
			synth = nil;
		});

		// Free the beat listener and the reset listener
		try { OSCdef(oscDefName).free; };
		try { OSCdef(("metro_output_reset_" ++ outputID).asSymbol).free; };
	}
}

/*
=============================================================================
CHANGES FROM TEMPLATE (template_output.scd → buffer_play_output.scd)
=============================================================================

1. EXTERNAL SYNTHDEF:
   - SynthDef is in: synthdefs/buffer_player_synth.scd
   - Listed in @meta requiredSynthdefs for auto-loading
   - System loads it via preset's synthdefs array

2. METADATA (@meta):
   - Template: name: \templateOutput, requiredInputType: nil
   - Changed to: name: \bufferPlayOutput, requiredInputType: \bufferRecord
   - Added requiredSynthdefs: ["buffer_player_synth.scd"]
   - Specified parameters: bufRate, ampScale, pan, duration

3. CONFIG EXTRACTION:
   - Template: outputID, sourceID, triggerBar, triggerBeat, duration
   - Added: ampScale, bufRate, pan (buffer-specific parameters)

4. TRIGGER LOGIC:
   - Template: Placeholder comment showing structure
   - Implemented: Check for Buffer or Event[\buffer], create Synth

5. BUFFER TYPE HANDLING:
   - Checks if sourceData is Buffer directly
   - Also handles Event with \buffer key (for onset slicing, etc.)

6. SYNTH CREATION:
   - Uses \bufferPlayOutputSynth with params: bufNum, bufRate, amp, pan
   - PlayBuf handles synth lifetime (doneAction: 2)

7. CLEANUP:
   - Kept identical: frees synth and OSCdef
   - Does NOT free buffers (main controller handles that)

=============================================================================
FILE STRUCTURE
=============================================================================

sc/routines/
├── outputs/
│   └── buffer_play_output.scd    <-- This file (routine function only)
└── synthdefs/
    └── buffer_player_synth.scd   <-- External SynthDef (loaded via preset)

=============================================================================
USAGE IN PRESET FILES
=============================================================================

In presets/mypreset.preset:

(
    synthdefs: ["buffer_player_synth.scd"],  // Auto-added via requiredSynthdefs
    
    outputs: [
        (
            id: \bufOut1,
            type: \bufferPlayOutput,     // Matches @meta name
            source: \recBuf1,            // ID of input routine that recorded buffer
            bar: 5,
            beat: 1,
            duration: 2.0,               // Not used - buffer determines length
            ampScale: 0.6,               // Volume
            pan: -0.3,                   // Pan left
            bufRate: 1.2                 // 20% faster playback
        )
    ]
)

=============================================================================
*/
