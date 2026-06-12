// JSON Note Input Template
// Dual runtime modes:
//   - \spawnPerNote: spawn one synth (or inline voice) per note event
//   - \longLived: create one synth and apply note events as parameter updates
//
// @meta: (
//   name: \jsonNoteInputTemplate,
//   displayName: "JSON Note Input Template",
//   category: \input,
//   requiredSynthdefs: [],
//   parameters: [
//     (name: \runtimeMode, default: \spawnPerNote, type: \choice, options: [\spawnPerNote, \longLived], label: "Runtime Mode"),
//     (name: \patternFile, default: "", type: \file, label: "Pattern JSON File", fileExtensions: ["json"]),
//     (name: \patternLoop, default: false, type: \bool, label: "Loop Pattern"),
//     (name: \synthDefName, default: "", type: \text, label: "SynthDef Name (optional)"),
//     (name: \usePitch, default: true, type: \bool, label: "Use Pitch"),
//     (name: \useFrequency, default: true, type: \bool, label: "Use Frequency"),
//     (name: \useAmplitude, default: true, type: \bool, label: "Use Amplitude"),
//     (name: \pitchArgName, default: "pitch", type: \text, label: "Pitch Arg Name"),
//     (name: \freqArgName, default: "freq", type: \text, label: "Frequency Arg Name"),
//     (name: \ampArgName, default: "amp", type: \text, label: "Amplitude Arg Name"),
//     (name: \durArgName, default: "durSec", type: \text, label: "Duration Arg Name"),
//     (name: \triggerArgName, default: "trig", type: \text, label: "Trigger Arg Name"),
//     (name: \envType, default: \linen, type: \choice, options: [\perc, \linen, \triangle, \sine, \asr, \adsr, \cutoff], label: "Env Type", showIf: (runtimeMode: \spawnPerNote)),
//     (name: \envCurve, default: -4, type: \float, min: -8, max: 8, label: "Env Curve", showIf: (runtimeMode: \spawnPerNote)),
//     (name: \envAttack, default: 0.01, type: \float, min: 0.001, max: 5, label: "Env Attack (s)", showIf: (runtimeMode: \spawnPerNote)),
//     (name: \envDecay, default: 0.08, type: \float, min: 0.001, max: 5, label: "Env Decay (s)", showIf: (runtimeMode: \spawnPerNote)),
//     (name: \envSustain, default: 0.7, type: \float, min: 0, max: 1, label: "Env Sustain", showIf: (runtimeMode: \spawnPerNote)),
//     (name: \envRelease, default: 0.08, type: \float, min: 0.001, max: 5, label: "Env Release (s)", showIf: (runtimeMode: \spawnPerNote)),
//     (name: \envLevel, default: 1.0, type: \float, min: 0, max: 2, label: "Env Level", showIf: (runtimeMode: \spawnPerNote))
//   ]
// )
{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats, outBus, targetGroup;
	var runtimeMode, patternLoop, synthDefName;
	var usePitch, useFrequency, useAmplitude;
	var pitchArgName, freqArgName, ampArgName, durArgName, triggerArgName;
	var envType, envTypeIndex, envCurve, envAttack, envDecay, envSustain, envRelease, envLevel;
	var oscDefName, resetDefName;
	var isActive = false, isComplete = false;
	var longSynth = nil, activeSynths = List.new;
	var scheduleToken = 0, pattern = nil;
	var cancelScheduled, freeActiveSynths, makeFiniteEnv, makeSpawnArgs;
	var runSpawnPerNote, runLongLived, runMode;

	inputID = config[\id];
	startBar = config[\startBar] ? 1;
	startBeat = config[\startBeat] ? 1;
	durationBeats = (config[\durationBeats] ? 4).asFloat.max(0.001);
	outBus = config[\outBus] ? 0;
	targetGroup = config[\group];

	runtimeMode = (config[\runtimeMode] ? \spawnPerNote).asSymbol;
	patternLoop = (config[\patternLoop] ? false).asBoolean;
	synthDefName = (config[\synthDefName] ? "").asString.stripWhiteSpace;

	usePitch = (config[\usePitch] ? true).asBoolean;
	useFrequency = (config[\useFrequency] ? true).asBoolean;
	useAmplitude = (config[\useAmplitude] ? true).asBoolean;

	pitchArgName = (config[\pitchArgName] ? "pitch").asString.asSymbol;
	freqArgName = (config[\freqArgName] ? "freq").asString.asSymbol;
	ampArgName = (config[\ampArgName] ? "amp").asString.asSymbol;
	durArgName = (config[\durArgName] ? "durSec").asString.asSymbol;
	triggerArgName = (config[\triggerArgName] ? "trig").asString.asSymbol;

	envType = (config[\envType] ? \linen).asSymbol;
	envTypeIndex = [\perc, \linen, \triangle, \sine, \asr, \adsr, \cutoff].indexOf(envType) ? 1;
	envCurve = config[\envCurve] ? -4;
	envAttack = (config[\envAttack] ? 0.01).asFloat.max(0.001);
	envDecay = (config[\envDecay] ? 0.08).asFloat.max(0.001);
	envSustain = (config[\envSustain] ? 0.7).asFloat.clip(0, 1);
	envRelease = (config[\envRelease] ? 0.08).asFloat.max(0.001);
	envLevel = (config[\envLevel] ? 1.0).asFloat.max(0);

	oscDefName = ("metro_input_" ++ inputID).asSymbol;
	resetDefName = ("metro_input_reset_" ++ inputID).asSymbol;

	if(~jsonNoteHelpers.isNil, {
		var helperPath = thisProcess.nowExecutingPath.dirname +/+ "../json_note_helpers.scd";
		if(File.exists(helperPath), { helperPath.load; });
	});

	pattern = if(~jsonNoteHelpers.notNil, {
		~jsonNoteHelpers[\normalizePattern].value(
			~jsonNoteHelpers[\loadPatternData].value(config)
		)
	}, { nil });

	cancelScheduled = {
		scheduleToken = scheduleToken + 1;
	};

	freeActiveSynths = {
		if(activeSynths.size > 0, {
			server.sendMsg('/error', -1);
			activeSynths.do { |s| try { s.free; }; };
			server.sendMsg('/error', -2);
		});
		activeSynths.clear;
	};

	makeFiniteEnv = { |durSec|
		var sustainSec, holdSec;
		sustainSec = (durSec - envAttack - envRelease).max(0.001);
		holdSec = (durSec - envAttack - envDecay - envRelease).max(0.001);

		switch(envType,
			\perc, { Env.perc(envAttack, (durSec - envAttack).max(0.001), envLevel, envCurve) },
			\linen, { Env.linen(envAttack, sustainSec, envRelease, envLevel, envCurve) },
			\triangle, { Env.triangle(durSec.max(0.002), envLevel) },
			\sine, { Env.sine(durSec.max(0.002), envLevel) },
			\asr, { Env.linen(envAttack, sustainSec, envRelease, envLevel, envCurve) },
			\adsr, { Env([0, envLevel, envLevel * envSustain, 0], [envAttack, envDecay + holdSec, envRelease], envCurve) },
			\cutoff, { Env([0, envLevel, envLevel, 0], [0.001, (durSec - envRelease).max(0.001), envRelease], envCurve) },
			{ Env.linen(envAttack, sustainSec, envRelease, envLevel, envCurve) }
		)
	};

	makeSpawnArgs = { |noteEvent|
		var args = List.new;
		args.addAll([\outBus, outBus, durArgName, noteEvent[\durSec]]);

		if(usePitch && noteEvent[\pitch].notNil, { args.addAll([pitchArgName, noteEvent[\pitch]]); });
		if(useFrequency && noteEvent[\frequency].notNil, { args.addAll([freqArgName, noteEvent[\frequency]]); });
		if(useAmplitude && noteEvent[\amplitude].notNil, { args.addAll([ampArgName, noteEvent[\amplitude]]); });
		args.addAll([\envType, envTypeIndex, \envAttack, envAttack, \envDecay, envDecay, \envSustain, envSustain, \envRelease, envRelease, \envLevel, envLevel, \envCurve, envCurve]);
		args.asArray
	};

	runSpawnPerNote = { |bpm|
		var beatDuration, totalDurSec, cycleDurBeats, loopCount, notes;
		if(pattern.isNil, {
			("[INPUT %] No pattern loaded".format(inputID)).postln;
		}, {
			beatDuration = 60.0 / bpm.asFloat.max(1);
			totalDurSec = durationBeats * beatDuration;
			notes = ~jsonNoteHelpers[\buildNoteEvents].value(pattern, startBar, startBeat, bpm, durationBeats);
			cycleDurBeats = pattern[\cycleDuration] ? durationBeats;
			loopCount = if(patternLoop && (cycleDurBeats > 0), {
				(durationBeats / cycleDurBeats).ceil.asInteger.max(1)
			}, { 1 });

			loopCount.do { |loopIdx|
				var loopOffsetBeats = loopIdx * cycleDurBeats;
				var loopOffsetSec = loopOffsetBeats * beatDuration;

				notes.do { |noteEvent|
					var localToken = scheduleToken;
					var eventDelay = noteEvent[\startDelaySec] + loopOffsetSec;
					var absoluteBeat = (noteEvent[\startTimeBeats] + loopOffsetBeats).floor.asInteger;
					var mapped = ~jsonNoteHelpers[\mapBeatIndexToBarBeat].value(
						absoluteBeat, startBar, startBeat, pattern[\beatsPerBar]
					);

					if(eventDelay < totalDurSec, {
						SystemClock.sched(eventDelay, {
							if(localToken == scheduleToken, {
								var s, noteAmp, noteFreq;
								noteAmp = noteEvent[\amplitude] ? 0.5;
								noteFreq = noteEvent[\frequency] ? noteEvent[\pitch].midicps;

								if(synthDefName.notEmpty, {
									s = Synth(synthDefName.asSymbol, makeSpawnArgs.value(noteEvent), targetGroup ? server);
									activeSynths.add(s);
								}, {
									s = {
										var env = EnvGen.kr(makeFiniteEnv.value(noteEvent[\durSec]), doneAction: 2);
										var sig = SinOsc.ar(noteFreq) * noteAmp * env;
										Out.ar(outBus, sig ! 2);
									}.play(targetGroup ? server);
									activeSynths.add(s);
								});

								"[INPUT %] note start mapped=%:% beatIndex=% dur=%.3fs".format(
									inputID, mapped[\bar], mapped[\beat], absoluteBeat, noteEvent[\durSec]
								).postln;

								SystemClock.sched(noteEvent[\durSec], {
									if(localToken == scheduleToken, {
										"[INPUT %] note end mapped=%:% beatIndex=%".format(
											inputID, mapped[\bar], mapped[\beat], absoluteBeat
										).postln;
									});
									nil;
								});
							});
							nil;
						});
					});
				};
			};
		});
	};

	runLongLived = { |bpm|
		var beatDuration, totalDurSec, cycleDurBeats, loopCount, notes;
		if(pattern.isNil, {
			("[INPUT %] No pattern loaded".format(inputID)).postln;
		}, {
			if(longSynth.isNil && synthDefName.notEmpty, {
				longSynth = Synth(synthDefName.asSymbol, [\inBus, audioInputBus, \outBus, outBus], targetGroup ? server);
			});

			beatDuration = 60.0 / bpm.asFloat.max(1);
			totalDurSec = durationBeats * beatDuration;
			notes = ~jsonNoteHelpers[\buildNoteEvents].value(pattern, startBar, startBeat, bpm, durationBeats);
			cycleDurBeats = pattern[\cycleDuration] ? durationBeats;
			loopCount = if(patternLoop && (cycleDurBeats > 0), {
				(durationBeats / cycleDurBeats).ceil.asInteger.max(1)
			}, { 1 });

			loopCount.do { |loopIdx|
				var loopOffsetBeats = loopIdx * cycleDurBeats;
				var loopOffsetSec = loopOffsetBeats * beatDuration;

				notes.do { |noteEvent|
					var localToken = scheduleToken;
					var eventDelay = noteEvent[\startDelaySec] + loopOffsetSec;
					var absoluteBeat = (noteEvent[\startTimeBeats] + loopOffsetBeats).floor.asInteger;
					var mapped = ~jsonNoteHelpers[\mapBeatIndexToBarBeat].value(
						absoluteBeat, startBar, startBeat, pattern[\beatsPerBar]
					);

					if(eventDelay < totalDurSec, {
						SystemClock.sched(eventDelay, {
							if(localToken == scheduleToken, {
								if(longSynth.notNil, {
									var args = List.new;
									if(usePitch && noteEvent[\pitch].notNil, { args.addAll([pitchArgName, noteEvent[\pitch]]); });
									if(useFrequency && noteEvent[\frequency].notNil, { args.addAll([freqArgName, noteEvent[\frequency]]); });
									if(useAmplitude && noteEvent[\amplitude].notNil, { args.addAll([ampArgName, noteEvent[\amplitude]]); });
									args.addAll([durArgName, noteEvent[\durSec], triggerArgName, 1]);
									longSynth.set(*args.asArray);

									SystemClock.sched(0.01, {
										if(localToken == scheduleToken && longSynth.notNil, {
											longSynth.set(triggerArgName, 0);
										});
										nil;
									});
								});

								"[INPUT %] long-lived note start mapped=%:% beatIndex=%".format(
									inputID, mapped[\bar], mapped[\beat], absoluteBeat
								).postln;

								SystemClock.sched(noteEvent[\durSec], {
									if(localToken == scheduleToken, {
										"[INPUT %] long-lived note end mapped=%:% beatIndex=%".format(
											inputID, mapped[\bar], mapped[\beat], absoluteBeat
										).postln;
									});
									nil;
								});
							});
							nil;
						});
					});
				};
			};
		});
	};

	runMode = { |bpm|
		if(runtimeMode == \longLived, {
			runLongLived.value(bpm);
		}, {
			runSpawnPerNote.value(bpm);
		});
	};

	OSCdef(resetDefName, { |msg|
		cancelScheduled.value;
		freeActiveSynths.value;
		if(longSynth.notNil, { try { longSynth.set(\gate, 0); longSynth.free; }; longSynth = nil; });
		isActive = false;
		isComplete = false;
		"[INPUT %] Reset complete".format(inputID).postln;
	}, '/metronome/reset');

	OSCdef(oscDefName, { |msg|
		var bar = msg[1].asInteger;
		var beat = msg[2].asInteger;
		var bpm = msg[3].asInteger;

		if((bar == startBar.asInteger) && (beat == startBeat.asInteger) && isActive.not && isComplete.not, {
			isActive = true;
			"[INPUT %] START mode=% dur=% beats".format(inputID, runtimeMode, durationBeats).postln;
			cancelScheduled.value;
			runMode.value(bpm);

			SystemClock.sched(durationBeats * (60.0 / bpm.asFloat.max(1)), {
				isActive = false;
				isComplete = true;
				freeActiveSynths.value;
				if(longSynth.notNil, { try { longSynth.set(\gate, 0); longSynth.free; }; longSynth = nil; });
				"[INPUT %] STOP".format(inputID).postln;
				nil;
			});
		});
	}, '/metronome');

	{
		cancelScheduled.value;
		freeActiveSynths.value;
		if(longSynth.notNil, { try { longSynth.set(\gate, 0); longSynth.free; }; longSynth = nil; });
		try { OSCdef(oscDefName).free; };
		try { OSCdef(resetDefName).free; };
	}
}
