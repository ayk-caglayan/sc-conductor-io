// Pitch Sonify Output Routine
// Plays back a stored pitch trajectory from a \storePitches input as a
// sequence of sine tones using Pbind. Each pitch point becomes one note
// whose duration scales with legato and the total requested duration.
//
// @meta: (
//   name: \pitchSonify,
//   displayName: "Pitch Sonify",
//   category: \output,
//   requiredInputType: \storePitches,
//   requiredSynthdefs: ["pitch_sonifier.scd"],
//   parameters: [
//     (name: \duration,    default: 4.0,  min: 0.5, max: 64,   type: \float, label: "Duration (beats)"),
//     (name: \ampScale,    default: 0.2,  min: 0.0, max: 1.0,  type: \float, label: "Amplitude"),
//     (name: \legato,      default: 0.5,  min: 0.0, max: 2.0,  type: \float, label: "Legato (note overlap)"),
//     (name: \attackTime,  default: 0.005,min: 0.001,max: 1.0, type: \float, label: "Attack (s)"),
//     (name: \releaseTime, default: 0.15, min: 0.01, max: 5.0, type: \float, label: "Release (s)")
//   ]
// )

{ |bufferDict, config, server|
	var outputID, sourceID, triggerBar, triggerBeat, duration;
	var ampScale, legato, attackTime, releaseTime;
	var outBus, targetGroup;
	var hasTriggered, player, oscDefName;

	outputID    = config[\id];
	sourceID    = config[\source];
	triggerBar  = config[\bar];
	triggerBeat = config[\beat];
	duration    = config[\duration]    ? 4.0;
	ampScale    = config[\ampScale]    ? 0.2;
	legato      = config[\legato]      ? 0.5;
	attackTime  = config[\attackTime]  ? 0.005;
	releaseTime = config[\releaseTime] ? 0.15;
	outBus      = config[\outBus]      ? 0;
	targetGroup = config[\group];

	hasTriggered = false;
	player       = nil;
	oscDefName   = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Pitch Sonify registered: trigger=%:%, source=%, duration=%".format(
		outputID, triggerBar, triggerBeat, sourceID, duration
	).postln;

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
		if(player.notNil, { try { player.stop; }; player = nil;
			"[OUTPUT %] Reset - stopped pitch pattern".format(outputID).postln;
		});
		hasTriggered = false;
		"[OUTPUT %] Reset - ready at %:%".format(outputID, triggerBar, triggerBeat).postln;
	}, '/metronome/reset');

	OSCdef(oscDefName, { |msg|
		var bar, beat, bpm;
		bar  = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm  = msg[3].asInteger;

		if((bar == triggerBar) && (beat == triggerBeat) && hasTriggered.not, {
			var sourceData, pitches, durSec, noteDur;

			hasTriggered = true;
			durSec = (duration / bpm) * 60;

			"[OUTPUT %] *** TRIGGERED at Bar %:% (% beats = % sec at % BPM)".format(
				outputID, bar, beat, duration, durSec.round(0.01), bpm
			).postln;

			sourceData = bufferDict[sourceID];

			if(sourceData.isNil, {
				"[OUTPUT %] ERROR: Source % not found in bufferDict!".format(outputID, sourceID).postln;
			}, {
				if(sourceData.isKindOf(Event) && sourceData[\pitches].notNil, {
					pitches = sourceData[\pitches];

					if(pitches.size == 0, {
						"[OUTPUT %] WARNING: No pitches stored in source %".format(outputID, sourceID).postln;
					}, {
						// Distribute total duration evenly across all pitch points
						noteDur = (durSec / pitches.size).max(0.01);

						"  Playing % pitches over % sec (% sec/note, legato=%)".format(
							pitches.size, durSec.round(0.01), noteDur.round(0.001), legato
						).postln;

						player = Pbind(
							\instrument,   \pitchSonifier,
							\freq,         Pseq(pitches.collect { |p| p.max(20) }, 1),
							\amp,          ampScale,
							\out,          outBus,
							\attackTime,   attackTime,
							\releaseTime,  releaseTime,
							\dur,          noteDur,
							\legato,       legato,
							\sustain,      noteDur * legato
						).play;
					});
				}, {
					"[OUTPUT %] ERROR: Source % is not storePitches data (got %)".format(
						outputID, sourceID, sourceData.class
					).postln;
				});
			});
		});
	}, '/metronome');

	{
		"[OUTPUT %] Cleanup called".format(outputID).postln;
		if(player.notNil, { try { player.stop; }; player = nil; });
		try { OSCdef(oscDefName).free; };
		try { OSCdef(("metro_output_reset_" ++ outputID).asSymbol).free; };
	}
}
