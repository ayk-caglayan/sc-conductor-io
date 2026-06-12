// Shared JSON note helpers for reusable input/output templates.
// Provides loading, normalization, beat-index mapping, and event scheduling helpers.
(
~jsonNoteHelpers = (
	getAny: { |dict, keys, default|
		var val = nil;
		keys.do { |k|
			if(val.isNil && dict.notNil, {
				val = dict[k];
				if(val.isNil, { val = dict[k.asString]; });
				if(val.isNil, { val = dict[k.asSymbol]; });
			});
		};
		val ? default;
	},

	parseJsonText: { |content|
		var asSC, parsed, result, i, len;
		asSC = content.asString;

		// Pass 1 – convert "key": value  ->  key: value
		// and keep "stringValue" as "stringValue".
		// Walk character by character to distinguish keys from string values.
		result = "";
		i = 0;
		len = asSC.size;
		while({ i < len }, {
			if(asSC[i] == $", {
				var keyStart, keyEnd, afterKey, key;
				keyStart = i + 1;
				keyEnd = asSC.find("\"", false, keyStart);
				if(keyEnd.notNil, {
					key = asSC.copyRange(keyStart, keyEnd - 1);
					afterKey = keyEnd + 1;
					while({ (afterKey < len) && ((asSC[afterKey] == $ ) || (asSC[afterKey] == $\t) || (asSC[afterKey] == $\n) || (asSC[afterKey] == $\r)) }, {
						afterKey = afterKey + 1;
					});
					if((afterKey < len) && (asSC[afterKey] == $:), {
						result = result ++ key ++ ":";
						i = afterKey + 1;
					}, {
						result = result ++ "\"" ++ key ++ "\"";
						i = keyEnd + 1;
					});
				}, {
					result = result ++ asSC[i];
					i = i + 1;
				});
			}, {
				result = result ++ asSC[i];
				i = i + 1;
			});
		});
		asSC = result;

		// Pass 2 – convert JSON delimiters and keywords
		asSC = asSC.replace("{", "(");
		asSC = asSC.replace("}", ")");
		asSC = asSC.replace("null", "nil");
		asSC = asSC.replace("true", "true");
		asSC = asSC.replace("false", "false");

		parsed = nil;
		try {
			parsed = asSC.interpret;
		} { |err|
			("[JSON] Parse error – could not interpret converted text").postln;
			parsed = nil;
		};
		parsed;
	},

	loadPatternData: { |config|
		var patternData, path, file, content, result;

		patternData = config[\patternData];
		if(patternData.notNil, {
			result = patternData;
		}, {
			path = config[\patternFile];
			if(path.isNil || (path.asString.stripWhiteSpace.size == 0), {
				result = nil;
			}, {
				file = File(path.asString, "r");
				if(file.isOpen.not, {
					("[JSON] Could not open pattern file: " ++ path).postln;
					result = nil;
				}, {
					content = file.readAllString;
					file.close;
					result = ~jsonNoteHelpers[\parseJsonText].value(content);
				});
			});
		});
		result;
	},

	beatsPerBarFromPattern: { |pattern|
		var ts, bpmBar, result;
		bpmBar = (~jsonNoteHelpers[\getAny].value(pattern, [\numBeats], nil));
		if(bpmBar.notNil, {
			result = bpmBar.asInteger.max(1);
		}, {
			ts = ~jsonNoteHelpers[\getAny].value(pattern, [\timeSignature], nil);
			if(ts.notNil, {
				var parts = ts.asString.split($/);
				if(parts.size >= 1, {
					result = parts[0].asInteger.max(1);
				}, {
					result = 4;
				});
			}, {
				result = 4;
			});
		});
		result;
	},

	normalizePattern: { |patternRaw|
		var notesRaw, cycleDuration, beatsPerBar, normalizedNotes, result;
		var warnings = List.new;

		if(patternRaw.isNil, {
			result = nil;
		}, {
			notesRaw = ~jsonNoteHelpers[\getAny].value(patternRaw, [\notes], []);
			cycleDuration = ~jsonNoteHelpers[\getAny].value(patternRaw, [\cycleDuration], nil);
			beatsPerBar = ~jsonNoteHelpers[\beatsPerBarFromPattern].value(patternRaw);

			normalizedNotes = notesRaw.collect { |n, idx|
				var startTime, duration, beatIndex, expectedBeatIndex, intraBeatOffset;
				var pitch, frequency, amplitude, strokeClass;

				startTime = (~jsonNoteHelpers[\getAny].value(n, [\startTime], 0)).asFloat.max(0);
				duration = (~jsonNoteHelpers[\getAny].value(n, [\duration], 0.25)).asFloat.max(0.001);
				beatIndex = (~jsonNoteHelpers[\getAny].value(n, [\beatIndex], startTime.floor)).asInteger;
				expectedBeatIndex = startTime.floor.asInteger;
				intraBeatOffset = (startTime - beatIndex).asFloat;

				if(beatIndex != expectedBeatIndex, {
					warnings.add("note % beatIndex mismatch (got %, expected %)".format(
						idx, beatIndex, expectedBeatIndex
					));
				});

				pitch = ~jsonNoteHelpers[\getAny].value(n, [\pitch], nil);
				frequency = ~jsonNoteHelpers[\getAny].value(n, [\frequency], nil);
				amplitude = ~jsonNoteHelpers[\getAny].value(n, [\amplitude], nil);
				strokeClass = ~jsonNoteHelpers[\getAny].value(n, [\strokeClass], nil);

				(
					startTime: startTime,
					duration: duration,
					beatIndex: beatIndex,
					intraBeatOffset: intraBeatOffset,
					pitch: if(pitch.notNil, { pitch.asFloat }, { nil }),
					frequency: if(frequency.notNil, { frequency.asFloat }, { nil }),
					amplitude: if(amplitude.notNil, { amplitude.asFloat }, { nil }),
					strokeClass: if(strokeClass.notNil, { strokeClass.asString.asSymbol }, { nil })
				)
			}.sortBy(\startTime);

			result = (
				bpm: (~jsonNoteHelpers[\getAny].value(patternRaw, [\bpm], nil)),
				numBeats: (~jsonNoteHelpers[\getAny].value(patternRaw, [\numBeats], beatsPerBar)),
				subdivisions: (~jsonNoteHelpers[\getAny].value(patternRaw, [\subdivisions], nil)),
				timeSignature: (~jsonNoteHelpers[\getAny].value(patternRaw, [\timeSignature], nil)),
				cycleDuration: if(cycleDuration.notNil, { cycleDuration.asFloat.max(0.001) }, { nil }),
				beatsPerBar: beatsPerBar,
				notes: normalizedNotes,
				warnings: warnings
			);
		});
		result;
	},

	mapBeatIndexToBarBeat: { |relativeBeat, anchorBar, anchorBeat, beatsPerBar|
		var absoluteBeatZero, barOffset, mappedBar, mappedBeat;
		absoluteBeatZero = (anchorBeat.asInteger - 1) + relativeBeat.asInteger;
		barOffset = (absoluteBeatZero / beatsPerBar.asInteger.max(1)).floor.asInteger;
		mappedBar = anchorBar.asInteger + barOffset;
		mappedBeat = (absoluteBeatZero % beatsPerBar.asInteger.max(1)) + 1;
		(
			bar: mappedBar,
			beat: mappedBeat
		)
	},

	buildNoteEvents: { |pattern, anchorBar, anchorBeat, bpm|
		var beatDuration, noteEvents, notesToUse, maxBeats, result;
		if(pattern.isNil, {
			result = [];
		}, {
			beatDuration = 60.0 / bpm.asFloat.max(1);
			maxBeats = (pattern[\cycleDuration] ? 0).asFloat;
			notesToUse = pattern[\notes] ? [];

			noteEvents = List.new;
			notesToUse.do { |note|
				var mapped, startBeatOffset, durBeats, durSec;
				startBeatOffset = note[\startTime].asFloat;
				durBeats = note[\duration].asFloat.max(0.001);

				if((maxBeats <= 0) || (startBeatOffset < maxBeats), {
					mapped = ~jsonNoteHelpers[\mapBeatIndexToBarBeat].value(
						note[\beatIndex], anchorBar, anchorBeat, pattern[\beatsPerBar]
					);
					durSec = durBeats * beatDuration;
					noteEvents.add((
						startTimeBeats: startBeatOffset,
						startDelaySec: startBeatOffset * beatDuration,
						durBeats: durBeats,
						durSec: durSec,
						bar: mapped[\bar],
						beat: mapped[\beat],
						intraBeatOffset: note[\intraBeatOffset],
						pitch: note[\pitch],
						frequency: note[\frequency],
						amplitude: note[\amplitude],
						strokeClass: note[\strokeClass]
					));
				});
			};

			result = noteEvents.asArray.sortBy(\startDelaySec);
		});
		result;
	},

	printPatternSummary: { |routineID, pattern, anchorBar, anchorBeat, runtimeMode, totalDurationBeats|
		var notes, beatsPerBar, bpm, line;
		if(pattern.isNil, {
			"[%] No pattern data loaded.".format(routineID).postln;
		}, {
			notes = pattern[\notes] ? [];
			beatsPerBar = pattern[\beatsPerBar] ? 4;
			bpm = pattern[\bpm];

			"".postln;
			"┌─── Pattern Summary: % ───".format(routineID).postln;
			"│ Mode: %  |  Notes: %  |  Duration: % beats".format(
				runtimeMode, notes.size, totalDurationBeats
			).postln;
			if(bpm.notNil, {
				"│ Pattern BPM: %  |  Time Sig: %  |  Cycle: % beats".format(
					bpm,
					pattern[\timeSignature] ? "?",
					pattern[\cycleDuration] ? "?"
				).postln;
			});
			"│ Anchor: bar % beat %  |  Beats/bar: %".format(
				anchorBar, anchorBeat, beatsPerBar
			).postln;
			"├───────────────────────────────────────────────".postln;
			"│  #  │ beat   │ bar:beat │ dur(b)  │ pitch │  freq   │  amp  │ class".postln;
			"├─────┼────────┼──────────┼─────────┼───────┼─────────┼───────┼──────".postln;

			notes.do { |n, idx|
				var mapped = ~jsonNoteHelpers[\mapBeatIndexToBarBeat].value(
					n[\beatIndex], anchorBar, anchorBeat, beatsPerBar
				);
				var pitchStr = if(n[\pitch].notNil, { n[\pitch].asInteger.asString.padLeft(5) }, { "    -" });
				var freqStr = if(n[\frequency].notNil, { n[\frequency].round(0.1).asString.padLeft(7) }, { "      -" });
				var ampStr = if(n[\amplitude].notNil, { n[\amplitude].round(0.001).asString.padLeft(5) }, { "    -" });
				var classStr = if(n[\strokeClass].notNil, { n[\strokeClass].asString }, { "-" });
				var durSec = n[\duration].round(0.0001).asString;

				"│ % │ % │   %:%   │ % │ % │ % │ % │ %".format(
					(idx + 1).asString.padLeft(3),
					n[\startTime].round(0.001).asString.padLeft(6),
					mapped[\bar].asString.padLeft(2),
					mapped[\beat].asString.padRight(2),
					durSec.padLeft(7),
					pitchStr,
					freqStr,
					ampStr,
					classStr
				).postln;
			};

			"└───────────────────────────────────────────────".postln;

			if(pattern[\warnings].notNil && (pattern[\warnings].size > 0), {
				"  ⚠ Warnings:".postln;
				pattern[\warnings].do { |w| ("    " ++ w).postln; };
			});
			"".postln;
		});
	}
);
)
