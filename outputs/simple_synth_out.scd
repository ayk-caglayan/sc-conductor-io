// Simple Synth Output Routine
// Produces a 300 Hz sine wave when triggered
//
// @meta: (
//   name: \simpleSynthOut,
//   displayName: "Simple Synth (300Hz Sine)",
//   category: \output,
//   requiredInputType: nil,
//   requiredSynthdefs: [],
//   parameters: [
//     (name: \duration, default: 4.0, min: 0.5, max: 64, type: \float, label: "Duration (beats)"),
//     (name: \ampScale, default: 0.3, min: 0, max: 1, type: \float, label: "Amplitude")
//   ]
// )

{ |bufferDict, config, server|
	var outputID, triggerBar, triggerBeat, duration, ampScale;
	var hasTriggered, synth, oscDefName;

	// Extract config
	outputID = config[\id];
	triggerBar = config[\bar];
	triggerBeat = config[\beat];
	duration = config[\duration] ? 4.0;
	ampScale = config[\ampScale] ? 0.3;

	// State
	hasTriggered = false;
	synth = nil;

	// Unique OSCdef name
	oscDefName = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Simple Synth registered: trigger=%:%, duration=% beats, amp=%".format(
		outputID, triggerBar, triggerBeat, duration, ampScale
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
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
		var bar, beat, bpm, beatDuration, synthDuration;

		bar = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm = msg[3].asInteger;

		// DEBUG: See incoming metronome messages
		// "DEBUG [OUTPUT %]: Received Bar %, Beat % (Waiting for %:%, triggered: %)".format(outputID, bar, beat, triggerBar, triggerBeat, hasTriggered).postln;

		// Trigger at specified bar:beat
		if((bar.asInteger == triggerBar.asInteger) && (beat.asInteger == triggerBeat.asInteger) && hasTriggered.not, {
			hasTriggered = true;
			beatDuration = 60.0 / bpm;
			synthDuration = duration * beatDuration;

			"[OUTPUT %] *** TRIGGERED at Bar %:% - Playing 300Hz sine for % sec".format(
				outputID, bar, beat, synthDuration.round(0.01)
			).postln;

			// Create simple sine synth directly (no SynthDef file needed)
			synth = {
				var sig, env;
				env = EnvGen.kr(
					Env.linen(0.01, synthDuration - 0.02, 0.01, 1),
					doneAction: 2
				);
				sig = SinOsc.ar(300) * ampScale * env;
				Out.ar(0, sig ! 2);
			}.play(server);
		});
	}, '/metronome');

	// =========================================================================
	// CLEANUP FUNCTION
	// =========================================================================

	{
		"[OUTPUT %] Cleanup called".format(outputID).postln;

		if(synth.notNil, {
			synth.free;
			synth = nil;
		});

		OSCdef(oscDefName).free;
		OSCdef(("metro_output_reset_" ++ outputID).asSymbol).free;
	}
}
