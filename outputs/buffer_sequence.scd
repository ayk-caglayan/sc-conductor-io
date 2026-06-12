// Buffer Sequence Output Routine
// Plays a recorded audio buffer with optional rate LFO modulation
// Similar to Buffer Player but adds rate modulation for evolving textures
//
// @meta: (
//   name: \bufferSequence,
//   displayName: "Buffer Sequence",
//   category: \output,
//   requiredInputType: \bufferRecord,
//   requiredSynthdefs: ["buffer_sequencer.scd"],
//   parameters: [
//     (name: \duration,   default: 4.0,  min: 0.5,  max: 64,   type: \float, label: "Duration (beats)"),
//     (name: \ampScale,   default: 0.6,  min: 0.0,  max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \bufRate,    default: 1.0,  min: 0.25, max: 4.0,  type: \float, label: "Playback Rate"),
//     (name: \pan,        default: 0.0,  min: -1.0, max: 1.0,  type: \float, label: "Pan"),
//     (name: \rateModAmt, default: 0.0,  min: 0.0,  max: 0.5,  type: \float, label: "Rate Mod Amount"),
//     (name: \rateModHz,  default: 0.1,  min: 0.01, max: 2.0,  type: \float, label: "Rate Mod Speed (Hz)"),
//     (name: \startPos,   default: 0.0,  min: 0.0,  max: 1.0,  type: \float, label: "Start Position (0-1)")
//   ]
// )

{ |bufferDict, config, server|
	var outputID, sourceID, triggerBar, triggerBeat, duration;
	var ampScale, bufRate, pan, rateModAmt, rateModHz, startPos;
	var outBus, targetGroup;
	var hasTriggered, synth, oscDefName;

	outputID    = config[\id];
	sourceID    = config[\source];
	triggerBar  = config[\bar];
	triggerBeat = config[\beat];
	duration    = config[\duration]   ? 4.0;
	ampScale    = config[\ampScale]   ? 0.6;
	bufRate     = config[\bufRate]    ? 1.0;
	pan         = config[\pan]        ? 0;
	rateModAmt  = config[\rateModAmt] ? 0.0;
	rateModHz   = config[\rateModHz]  ? 0.1;
	startPos    = config[\startPos]   ? 0.0;
	outBus      = config[\outBus]     ? 0;
	targetGroup = config[\group];

	hasTriggered = false;
	synth        = nil;
	oscDefName   = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Buffer Sequence registered: trigger=%:%, source=%, rate=%, amp=%".format(
		outputID, triggerBar, triggerBeat, sourceID, bufRate, ampScale
	).postln;

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
		if(synth.notNil, { try { synth.free; }; synth = nil;
			"[OUTPUT %] Reset - stopped in-progress playback".format(outputID).postln;
		});
		hasTriggered = false;
		"[OUTPUT %] Reset - ready to trigger again at %:%".format(outputID, triggerBar, triggerBeat).postln;
	}, '/metronome/reset');

	OSCdef(oscDefName, { |msg|
		var bar, beat, bpm;
		bar  = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm  = msg[3].asInteger;

		if((bar == triggerBar) && (beat == triggerBeat) && hasTriggered.not, {
			var sourceData, buf, durSec;

			hasTriggered = true;
			durSec = (duration / bpm) * 60;

			"[OUTPUT %] *** TRIGGERED at Bar %:% (% beats = % sec at % BPM)".format(
				outputID, bar, beat, duration, durSec.round(0.01), bpm
			).postln;

			sourceData = bufferDict[sourceID];

			if(sourceData.isNil, {
				"[OUTPUT %] ERROR: Source % not found in bufferDict!".format(outputID, sourceID).postln;
			}, {
				if(sourceData.isKindOf(Buffer), {
					buf = sourceData;
				}, {
					if(sourceData.isKindOf(Event) && sourceData[\buffer].notNil, {
						buf = sourceData[\buffer];
					});
				});

				if(buf.notNil && buf.isKindOf(Buffer), {
					synth = Synth(\bufferSequencer, [
						\bufNum,     buf.bufnum,
						\outBus,     outBus,
						\bufRate,    bufRate,
						\ampScale,   ampScale,
						\pan,        pan,
						\rateModAmt, rateModAmt,
						\rateModHz,  rateModHz,
						\startPos,   startPos,
						\durSec,     durSec
					], targetGroup ? server);
					"  Playing buffer % (bufnum=%) seq, duration=% sec".format(
						sourceID, buf.bufnum, durSec.round(0.01)
					).postln;
				}, {
					"[OUTPUT %] ERROR: Source % is not a Buffer".format(outputID, sourceID).postln;
				});
			});
		});
	}, '/metronome');

	{
		"[OUTPUT %] Cleanup called".format(outputID).postln;
		if(synth.notNil, { try { synth.free; }; synth = nil; });
		try { OSCdef(oscDefName).free; };
		try { OSCdef(("metro_output_reset_" ++ outputID).asSymbol).free; };
	}
}
