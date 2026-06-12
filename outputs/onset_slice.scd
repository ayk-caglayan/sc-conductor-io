// Onset Slice Output Routine
// Plays one slice of a buffer starting at a frame offset
// Source must be an Event with keys: buffer (Buffer), indices (Array of frames)
// Each trigger plays the slice at indices[sliceIndex] for duration beats
//
// @meta: (
//   name: \onsetSlice,
//   displayName: "Onset Slice",
//   category: \output,
//   requiredInputType: nil,
//   requiredSynthdefs: ["onset_slicer.scd"],
//   parameters: [
//     (name: \duration,   default: 2.0,  min: 0.1,  max: 32,   type: \float, label: "Duration (beats)"),
//     (name: \ampScale,   default: 0.6,  min: 0.0,  max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \bufRate,    default: 1.0,  min: 0.25, max: 4.0,  type: \float, label: "Playback Rate"),
//     (name: \pan,        default: 0.0,  min: -1.0, max: 1.0,  type: \float, label: "Pan"),
//     (name: \sliceIndex, default: 0,    min: 0,    max: 127,  type: \int,   label: "Slice Index")
//   ]
// )

{ |bufferDict, config, server|
	var outputID, sourceID, triggerBar, triggerBeat, duration;
	var ampScale, bufRate, pan, sliceIndex;
	var outBus, targetGroup;
	var hasTriggered, synth, oscDefName;

	outputID    = config[\id];
	sourceID    = config[\source];
	triggerBar  = config[\bar];
	triggerBeat = config[\beat];
	duration    = config[\duration]   ? 2.0;
	ampScale    = config[\ampScale]   ? 0.6;
	bufRate     = config[\bufRate]    ? 1.0;
	pan         = config[\pan]        ? 0;
	sliceIndex  = (config[\sliceIndex] ? 0).asInteger;
	outBus      = config[\outBus]     ? 0;
	targetGroup = config[\group];

	hasTriggered = false;
	synth        = nil;
	oscDefName   = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Onset Slice registered: trigger=%:%, source=%, sliceIndex=%, rate=%".format(
		outputID, triggerBar, triggerBeat, sourceID, sliceIndex, bufRate
	).postln;

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
		if(synth.notNil, { try { synth.free; }; synth = nil;
			"[OUTPUT %] Reset - stopped onset slice".format(outputID).postln;
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
			var sourceData, buf, indices, startFrame, durSec;

			hasTriggered = true;
			durSec = (duration / bpm) * 60;

			"[OUTPUT %] *** TRIGGERED at Bar %:% (duration: % beats = % sec)".format(
				outputID, bar, beat, duration, durSec.round(0.01)
			).postln;

			sourceData = bufferDict[sourceID];

			if(sourceData.isNil, {
				"[OUTPUT %] ERROR: Source % not found in bufferDict!".format(outputID, sourceID).postln;
			}, {
				// Source should be an Event with \buffer and \indices keys
				// If just a Buffer, play from frame 0
				if(sourceData.isKindOf(Buffer), {
					buf = sourceData;
					startFrame = 0;
				}, {
					if(sourceData.isKindOf(Event), {
						buf = sourceData[\buffer];
						indices = sourceData[\indices];
						if(indices.notNil && (sliceIndex < indices.size), {
							startFrame = indices[sliceIndex];
						}, {
							startFrame = 0;
						});
					});
				});

				if(buf.notNil && buf.isKindOf(Buffer), {
					synth = Synth(\onsetSlicer, [
						\bufNum,     buf.bufnum,
						\outBus,     outBus,
						\startFrame, startFrame ? 0,
						\durSec,     durSec,
						\bufRate,    bufRate,
						\ampScale,   ampScale,
						\pan,        pan
					], targetGroup ? server);
					"  Playing onset slice % from frame % for % sec".format(
						sliceIndex, startFrame, durSec.round(0.01)
					).postln;
				}, {
					"[OUTPUT %] ERROR: Source % has no valid buffer".format(outputID, sourceID).postln;
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
