// Routines - Main Controller
// Modular architecture with dynamic routine loading and unified buffer dictionary
//
// OSC messages received:
//   /metronome [bar, beat, bpm]  - per-beat tick from metronome.scd
//   /metronome/reset             - sent by metronome.scd on reset; each input/output
//                                  routine owns a second OSCdef (named
//                                  metro_input_reset_<id> or metro_output_reset_<id>)
//                                  that clears its one-shot state so it re-arms for
//                                  the next run without reloading routines.scd.
//
// Usage:
// 1. Edit presetPath to point to your preset file
// 2. Run this script
// 3. Start metronome.scd to trigger routines
// 4. Press Reset in metronome.scd to re-arm all routines without reloading
// 5. Call ~cleanup.value to stop and free resources
//
// Multi-stage FX chains (preset key \fxChains): source output → N buses → optional
// \instance input stage + \synthdef stages → \fxOutBus. Full refresher:
//   see README.md in this folder (groups, buses, /n_go /n_end lifecycle, old preset format).

(
// =============================================================================
// CONFIGURATION
// =============================================================================

var presetPath, presetData;
var basePath, synthdefPath, inputPath, outputPath;
var cleanupFuncs, audioInputBus;
var fxChains, fxBusDict, sourceGroup, fxGroup;

// Edit this path to load different presets
presetPath = thisProcess.nowExecutingPath.dirname +/+ "presets/grant_demo.preset";

// =============================================================================
// PRESET LOADING
// =============================================================================

~loadPresetFile = { |path|
	var file, content, data;
	file = File(path, "r");
	if(file.isOpen, {
		content = file.readAllString;
		file.close;
		data = content.interpret;
		data;
	}, {
		"Failed to open preset file: %".format(path).postln;
		nil;
	});
};

// =============================================================================
// INITIALIZATION
// =============================================================================

// =============================================================================
// AUTO-CLEANUP FROM PREVIOUS SESSION (AGGRESSIVE)
// =============================================================================

"".postln;
">>> Auto-cleaning up any previous sessions...".postln;

// 1. Call existing cleanup function if available
if(~cleanup.notNil && ~cleanup.isFunction, {
	"  Calling existing ~cleanup...".postln;
	try { ~cleanup.value; };
});

// 2. Aggressively free ALL OSCdefs matching our naming patterns
//    (catches orphaned OSCdefs from sessions that were overwritten)
//    Naming conventions:
//      metro_input_<id>        - per-beat beat listener for an input routine
//      metro_input_reset_<id>  - /metronome/reset listener for an input routine
//      metro_output_<id>       - per-beat beat listener for an output routine
//      metro_output_reset_<id> - /metronome/reset listener for an output routine
//    All four patterns are covered by the beginsWith checks below.
"  Freeing all routines OSCdefs...".postln;
OSCdef.all.keysValuesDo { |key, oscdef|
	var keyStr = key.asString;
	if(keyStr.beginsWith("metro_output_") ||
	   keyStr.beginsWith("metro_input_") ||
	   (key == \routines_debug_monitor), {
		"    Freed orphaned OSCdef: %".format(key).postln;
		oscdef.free;
	});
};

// 3. Free any remaining buffers in ~bufferDict
if(~bufferDict.notNil && ~bufferDict.isKindOf(IdentityDictionary), {
	"  Freeing remaining buffers in ~bufferDict...".postln;
	~bufferDict.keysValuesDo { |id, buf|
		if(buf.isKindOf(Buffer), {
			try { buf.free; };
			"    Freed orphaned buffer: %".format(id).postln;
		}, {
			if(buf.isKindOf(Event), {
				buf.keysValuesDo { |key, val|
					if(val.isKindOf(Buffer), {
						try { val.free; };
						"    Freed orphaned buffer: %[%]".format(id, key).postln;
					});
				};
			});
		});
	};
	~bufferDict.clear;
});

">>> Cleanup complete.".postln;
"".postln;

"=== Routines - Main Controller ===".postln;
"Loading preset: %".format(presetPath).postln;

presetData = ~loadPresetFile.value(presetPath);

if(presetData.isNil, {
	"ERROR: Could not load preset file. Aborting.".postln;
}, {
	// Initialize globals
	~bufferDict = IdentityDictionary.new;
	cleanupFuncs = List.new;
	audioInputBus = presetData[\audioInputBus] ? 0;

	// Set up paths
	basePath = thisProcess.nowExecutingPath.dirname;
	synthdefPath = basePath +/+ "synthdefs";
	inputPath = basePath +/+ "inputs";
	outputPath = basePath +/+ "outputs";

	// Load shared helpers (used by reusable JSON note templates)
	if(File.exists(basePath +/+ "json_note_helpers.scd"), {
		try { (basePath +/+ "json_note_helpers.scd").load; };
	});

	"Audio input bus: %".format(audioInputBus).postln;

	// =============================================================================
	// SERVER BOOT
	// =============================================================================

	s.waitForBoot({
		var inputs, outputs, synthdefs, preloadBuffers, inputLookup, outputLookup;

		"".postln;
		"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━".postln;
		"INITIALIZING ROUTINES".postln;
		"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━".postln;

		// =========================================================================
		// LOAD SYNTHDEFS FROM PRESET
		// =========================================================================

		synthdefs = presetData[\synthdefs] ? [];

		if(synthdefs.size > 0, {
			"[1/4] Loading SynthDefs...".postln;
			synthdefs.do { |synthdefFile|
				var fullPath;
				fullPath = synthdefPath +/+ synthdefFile;
				if(File.exists(fullPath), {
					"  ✓ %".format(synthdefFile).postln;
					fullPath.load;
				}, {
					"  ✗ WARNING: SynthDef not found: %".format(fullPath).postln;
				});
			};
			s.sync;
			"".postln;
		}, {
			"[1/4] No SynthDefs specified in preset.".postln;
			"".postln;
		});

		// =========================================================================
		// PRELOAD AUDIO BUFFERS
		// =========================================================================

		preloadBuffers = presetData[\preloadBuffers] ? [];

		if(preloadBuffers.size > 0, {
			"[2/4] Preloading Audio Buffers...".postln;
			preloadBuffers.do { |bufConfig|
				var id, path, buf;
				id = bufConfig[\id];
				path = bufConfig[\path];
				if(path.isKindOf(String) && (path[0] != $/), {
					path = (basePath +/+ path).standardizePath;
				});

				if(File.exists(path), {
					buf = Buffer.read(s, path);
					~bufferDict[id] = buf;
					"  ✓ % (%)".format(id, path.basename).postln;
				}, {
					"  ✗ WARNING: Audio file not found: %".format(path).postln;
				});
			};
			s.sync;
			"".postln;
		}, {
			"[2/4] No buffers to preload.".postln;
			"".postln;
		});

		// =========================================================================
		// FX CHAIN: GROUPS AND BUS ALLOCATION
		// See README.md — multi-stage chaining: sourceGroup + fxGroup, one bus per
		// stage, \fxStages with \synthdef and/or \instance, runtime via /n_go + /n_end.
		// =========================================================================

		fxChains = presetData[\fxChains] ? [];
		fxBusDict = IdentityDictionary.new;

		sourceGroup = Group.new(s);
		fxGroup = Group.after(sourceGroup);
		s.sync;

		"[FX] Source group: %, FX group: %".format(sourceGroup.nodeID, fxGroup.nodeID).postln;

		// Build lookup dicts so we can inject routing config before loading routines
		inputs = presetData[\inputs] ? [];
		outputs = presetData[\outputs] ? [];

		inputLookup = IdentityDictionary.new;
		inputs.do { |cfg| inputLookup[cfg[\id].asSymbol] = cfg; };
		outputLookup = IdentityDictionary.new;
		outputs.do { |cfg| outputLookup[cfg[\id].asSymbol] = cfg; };

		// -------------------------------------------------------------------------
		// NORMALIZE old single-stage format into fxStages array.
		// Old formats:
		//   (\source: \x, \fxSynthDef: \foo, \fxArgs: (), \fxOutBus: 0)
		//   (\source: \x, \fx: \inputID)
		// New format:
		//   (\source: \x, \fxStages: [(\synthDef: \foo, \args: ())], \fxOutBus: 0)
		//   (\source: \x, \fxStages: [(\mode: \instance, \fx: \inputID)], \fxOutBus: 0)
		// -------------------------------------------------------------------------
		fxChains = fxChains.collect { |chain|
			if(chain[\fxStages].isNil, {
				var stage;
				if(chain[\fxSynthDef].notNil, {
					stage = (\mode: \synthdef, \synthDef: chain[\fxSynthDef], \args: chain[\fxArgs] ? ());
				}, {
					stage = (\mode: \instance, \fx: chain[\fx]);
				});
				(\source: chain[\source], \fxStages: [stage], \fxOutBus: chain[\fxOutBus] ? 0);
			}, {
				chain;
			});
		};

		if(fxChains.size > 0, {
			"[FX] Allocating buses for % chain(s)...".postln;

			fxChains.do { |chain|
				// -----------------------------------------------------------------
				// Multi-stage chain setup.
				// For N stages, allocate N buses:
				//   bus[0]: source -> stage[0]
				//   bus[1]: stage[0] -> stage[1]
				//   ...
				//   bus[N-1]: stage[N-2] -> stage[N-1]
				// stage[N-1] writes to fxOutBus (hardware).
				// -----------------------------------------------------------------
				var srcID, stages, fxOutBus, buses, outCfg, entry;
				var goOSCName, endOSCName;

				srcID    = chain[\source].asSymbol;
				stages   = chain[\fxStages] ? [];
				fxOutBus = chain[\fxOutBus] ? 0;

				if(stages.size == 0, {
					"[FX] WARNING: chain for '%' has no stages, skipping".format(srcID).postln;
				}, {
					// Allocate one private bus per stage
					buses = stages.collect { Bus.audio(s, 1) };

					// Redirect source output into bus[0]
					outCfg = outputLookup[srcID];
					if(outCfg.notNil, {
						outCfg[\outBus] = buses[0].index;
						outCfg[\group]  = sourceGroup;
						"[FX] Output '%' -> bus % (sourceGroup)".format(srcID, buses[0].index).postln;
					}, {
						"[FX] WARNING: source '%' not found in outputs".format(srcID).postln;
					});

					// For each stage, determine inBus and outBus:
					//   inBus  = buses[i].index
					//   outBus = buses[i+1].index  (or fxOutBus for the last stage)
					stages.do { |stage, i|
						var inBusIdx  = buses[i].index;
						var outBusIdx = if(i < (stages.size - 1), { buses[i+1].index }, { fxOutBus });
						var stageMode = stage[\mode] ? \synthdef;

						if(stageMode == \instance, {
							// Input Instance stage: inject routing into the input config.
							// Only valid as stage 0 (first stage).
							var fxID  = stage[\fx].asSymbol;
							var inCfg = inputLookup[fxID];
							if(inCfg.notNil, {
								inCfg[\fxInBus]    = inBusIdx;
								inCfg[\useSoundIn] = 0;
								inCfg[\outBus]     = outBusIdx;
								inCfg[\group]      = fxGroup;
								"  Stage %: Instance '%' (bus % -> bus %)".format(i, fxID, inBusIdx, outBusIdx).postln;
							}, {
								"[FX] WARNING: instance '%' not found in inputs".format(fxID).postln;
							});
						});
						// SynthDef stages are handled at runtime via /n_go (see below).
					};

					// Build per-stage argLists for SynthDef stages (used in /n_go handler)
					entry = (
						buses:      buses,
						fxSynths:   Array.newClear(stages.size),
						stages:     stages,
						fxOutBus:   fxOutBus,
						goOSC:      nil,
						endOSC:     nil
					);
					fxBusDict[srcID] = entry;

					// Build argList for each SynthDef stage now (bus indices are stable)
					{
						var argLists = Array.newClear(stages.size);
						stages.do { |stage, i|
							var inBusIdx  = buses[i].index;
							var outBusIdx = if(i < (stages.size - 1), { buses[i+1].index }, { fxOutBus });
							var stageMode = stage[\mode] ? \synthdef;
							if(stageMode == \synthdef, {
								var args = stage[\args] ? ();
								argLists[i] = [\inBus, inBusIdx, \outBus, outBusIdx, \useSoundIn, 0] ++ args.asPairs;
							});
							// instance stages leave argLists[i] as nil
						};
						entry[\stageArgLists] = argLists;
					}.value;

					// Log the chain
					"  Chain '%': % stage(s), buses [%], finalOut: %".format(
						srcID,
						stages.size,
						buses.collect(_.index).join(", "),
						fxOutBus
					).postln;

					// -----------------------------------------------------------------
					// OSC lifecycle: /n_go creates all SynthDef-stage synths;
					//                /n_end releases them all.
					// -----------------------------------------------------------------
					goOSCName  = ("fxGo_"  ++ srcID).asSymbol;
					endOSCName = ("fxEnd_" ++ srcID).asSymbol;

					OSCdef(goOSCName, { |msg|
						var nodeID  = msg[1].asInteger;
						var groupID = msg[2].asInteger;
						if(groupID == sourceGroup.nodeID, {
							var newSynths = Array.newClear(stages.size);
							"[FX] Source '%' synth % started -> creating % FX stage(s)".format(srcID, nodeID, stages.size).postln;

							// Create all SynthDef stages in order (addToTail preserves order)
							stages.do { |stage, i|
								var stageMode = stage[\mode] ? \synthdef;
								if(stageMode == \synthdef, {
									var synthName = stage[\synthDef].asSymbol;
									var argList   = entry[\stageArgLists][i];
									var newFx     = Synth(synthName, argList, fxGroup, \addToTail);
									newSynths[i]  = newFx;
									"  Stage %: created Synth('%')".format(i, synthName).postln;
								});
							};
							entry[\fxSynths] = newSynths;

							// Watch for source node end, then release all FX synths
							OSCdef(endOSCName, { |endMsg|
								var endedNode = endMsg[1].asInteger;
								if(endedNode == nodeID, {
									"[FX] Source '%' synth % ended -> releasing % FX stage(s)".format(srcID, nodeID, stages.size).postln;
									// Release in reverse order for clean signal unwinding
									newSynths.reverseDo { |fx|
										if(fx.notNil, { try { fx.set(\gate, 0) } });
									};
									entry[\fxSynths] = Array.newClear(stages.size);
									OSCdef(endOSCName).free;
								});
							}, '/n_end');
						});
					}, '/n_go');

					entry[\goOSC]  = goOSCName;
					entry[\endOSC] = endOSCName;

					s.sendMsg('/notify', 1);
				});
			};

			s.sync;
			"".postln;
		}, {
			"[FX] No FX chains defined.".postln;
			"".postln;
		});

		"".postln;

		// =========================================================================
		// LOAD AND RUN INPUT ROUTINES
		// =========================================================================

		if(inputs.size > 0, {
			"[3/4] Loading Input Routines...".postln;
			inputs.do { |config|
				var routineFile, routineFunc, cleanup, fileName, typeStr;
				// Map type to filename: \bufferRecord -> "buffer_record.scd"
				// Convert camelCase to snake_case
				typeStr = config[\type].asString;
				fileName = "";
				typeStr.do { |char, i|
					if(char.isUpper && (i > 0), {
						fileName = fileName ++ "_" ++ char.toLower;
					}, {
						fileName = fileName ++ char.toLower;
					});
				};
				fileName = fileName ++ ".scd";
				routineFile = inputPath +/+ fileName;

				if(File.exists(routineFile), {
					"  Loading: % (id: %)".format(config[\type], config[\id]).postln;
					routineFunc = routineFile.load;

					if(routineFunc.isFunction, {
						// Pass bufferDict, config, server, audioInputBus to routine
						cleanup = routineFunc.value(~bufferDict, config, s, audioInputBus);
						if(cleanup.isFunction, {
							cleanupFuncs.add(cleanup);
						});
					}, {
						"    ✗ WARNING: % did not return a function".format(routineFile).postln;
					});
				}, {
					"    ✗ WARNING: Input routine not found: %".format(routineFile).postln;
				});
			};
			"  ✓ % input routine(s) loaded".format(inputs.size).postln;
			"".postln;
		}, {
			"[3/4] No input routines specified.".postln;
			"".postln;
		});

		// =========================================================================
		// LOAD AND RUN OUTPUT ROUTINES
		// =========================================================================

		if(outputs.size > 0, {
			"[4/4] Loading Output Routines...".postln;
			outputs.do { |config|
				var routineFile, routineFunc, cleanup, fileName, typeStr;
				// Map type to filename: \playBuffer -> "play_buffer.scd"
				// Convert camelCase to snake_case
				typeStr = config[\type].asString;
				fileName = "";
				typeStr.do { |char, i|
					if(char.isUpper && (i > 0), {
						fileName = fileName ++ "_" ++ char.toLower;
					}, {
						fileName = fileName ++ char.toLower;
					});
				};
				fileName = fileName ++ ".scd";
				routineFile = outputPath +/+ fileName;

		if(File.exists(routineFile), {
			"  Loading: % (id: %)".format(config[\type], config[\id]).postln;
			routineFunc = routineFile.load;

			if(routineFunc.isFunction, {
				// Pass bufferDict, config, server to routine
				cleanup = routineFunc.value(~bufferDict, config, s);
				if(cleanup.isFunction, {
					cleanupFuncs.add(cleanup);
				}, {
					"    ✗ WARNING: Cleanup function not returned".postln;
				});
			}, {
				"    ✗ WARNING: % did not return a function".format(routineFile).postln;
			});
		}, {
			"    ✗ WARNING: Output routine not found: %".format(routineFile).postln;
		});
			};
			"  ✓ % output routine(s) loaded".format(outputs.size).postln;
			"".postln;
		}, {
			"[4/4] No output routines specified.".postln;
			"".postln;
		});

		// =========================================================================
		// TIMELINE SUMMARY
		// =========================================================================
		{
			var timeline = List.new;
			var addJsonNotes = { |cfg, anchorBar, anchorBeat|
				if(~jsonNoteHelpers.notNil, {
					var pat = ~jsonNoteHelpers[\normalizePattern].value(
						~jsonNoteHelpers[\loadPatternData].value(cfg)
					);
					if(pat.notNil, {
						var notes = pat[\notes] ? [];
						var bpb = pat[\beatsPerBar] ? 4;
						notes.do { |n, idx|
							var mapped = ~jsonNoteHelpers[\mapBeatIndexToBarBeat].value(
								n[\beatIndex], anchorBar, anchorBeat, bpb
							);
							var durStr = n[\duration].round(0.001).asString ++ "b";
							timeline.add((
								sort: (mapped[\bar].asInteger * 1000) + mapped[\beat].asInteger + (n[\startTime].asFloat * 0.001),
								text: "         · note % │ %:% +% │ dur %".format(
									(idx + 1).asString.padLeft(3),
									mapped[\bar].asString.padLeft(2), mapped[\beat],
									n[\intraBeatOffset].round(0.001).asString.padLeft(5),
									durStr.padLeft(7)
								)
							));
						};
					});
				});
			};

			inputs.do { |cfg|
				var bar = cfg[\startBar] ? 1;
				var beat = cfg[\startBeat] ? 1;
				var dur = cfg[\durationBeats] ? cfg[\duration] ? "?";
				timeline.add((
					sort: (bar.asInteger * 1000) + beat.asInteger - 0.001,
					text: "  INPUT  % │ %:% │ % beats │ %".format(
						cfg[\id].asString.padRight(10),
						bar.asString.padLeft(2), beat,
						dur.asString.padLeft(5),
						cfg[\type]
					)
				));
				if(cfg[\type].asString.contains("jsonNote") || cfg[\type].asString.contains("JsonNote"), {
					addJsonNotes.value(cfg, bar, beat);
				});
			};

			outputs.do { |cfg|
				var bar = cfg[\bar] ? 1;
				var beat = cfg[\beat] ? 1;
				var dur;
				var extra = "";
				if((cfg[\type].asString.contains("jsonNote") || cfg[\type].asString.contains("JsonNote")) && ~jsonNoteHelpers.notNil, {
					var pat = ~jsonNoteHelpers[\normalizePattern].value(~jsonNoteHelpers[\loadPatternData].value(cfg));
					dur = if(pat.notNil && pat[\cycleDuration].notNil, { pat[\cycleDuration].asString }, { "auto" });
				}, {
					dur = (cfg[\duration] ? cfg[\durationBeats] ? "?").asString;
				});
				if(cfg[\runtimeMode].notNil, { extra = extra ++ " [%]".format(cfg[\runtimeMode]) });
				if(cfg[\synthDefName].notNil && (cfg[\synthDefName].asString.size > 0), {
					extra = extra ++ " synth:%".format(cfg[\synthDefName]);
				});
				timeline.add((
					sort: (bar.asInteger * 1000) + beat.asInteger - 0.001,
					text: "  OUTPUT % │ %:% │ % beats │ %%".format(
						cfg[\id].asString.padRight(10),
						bar.asString.padLeft(2), beat,
						dur.asString.padLeft(5),
						cfg[\type],
						extra
					)
				));
				if(cfg[\type].asString.contains("jsonNote") || cfg[\type].asString.contains("JsonNote"), {
					addJsonNotes.value(cfg, bar, beat);
				});
			};

			timeline = timeline.asArray.sort { |a, b| a[\sort] < b[\sort] };

			"".postln;
			"┌─── Event Timeline ───────────────────────────────────────────".postln;
			timeline.do { |ev| ("│" ++ ev[\text]).postln; };
			"└─────────────────────────────────────────────────────────────".postln;
		}.value;

		// =========================================================================
		// CLEANUP FUNCTION
		// =========================================================================

		~cleanup = {
			"Cleaning up...".postln;

			// Call all routine cleanup functions (frees synths and OSCdefs)
			cleanupFuncs.do { |fn|
				try { fn.value; };
			};
			cleanupFuncs.clear;
			"  Routine cleanups executed.".postln;

			// Free multi-stage FX synths, OSCdefs, and buses
			fxBusDict.keysValuesDo { |id, entry|
				if(entry[\goOSC].notNil, {
					try { OSCdef(entry[\goOSC]).free };
				});
				if(entry[\endOSC].notNil, {
					try { OSCdef(entry[\endOSC]).free };
				});
				// Free all stage synths (array)
				if(entry[\fxSynths].notNil, {
					entry[\fxSynths].do { |fx|
						if(fx.notNil, {
							try { fx.free; };
						});
					};
					"  Freed % FX stage synth(s) for: %".format(entry[\fxSynths].size, id).postln;
				});
				// Free all intermediate buses (array)
				if(entry[\buses].notNil, {
					entry[\buses].do { |bus|
						if(bus.notNil, {
							try { bus.free; };
						});
					};
					"  Freed % FX bus(es) for: %".format(entry[\buses].size, id).postln;
				});
			};
			fxBusDict.clear;

			// Free groups
			try { sourceGroup.free; };
			try { fxGroup.free; };
			"  Freed source/FX groups.".postln;

			// Free all buffers in dictionary
			~bufferDict.keysValuesDo { |id, buf|
				if(buf.isKindOf(Buffer), {
					buf.free;
					"  Freed buffer: %".format(id).postln;
				}, {
					if(buf.isKindOf(Event), {
						buf.keysValuesDo { |key, val|
							if(val.isKindOf(Buffer), {
								val.free;
								"  Freed buffer: %[%]".format(id, key).postln;
							});
						};
					});
				});
			};
			~bufferDict.clear;

			"Cleanup complete.".postln;
		};

		// =========================================================================
		// READY MESSAGE
		// =========================================================================

		// Add cleanup for debug OSCdef
		cleanupFuncs.add({
			"[ROUTINES DEBUG] Freeing debug OSCdef".postln;
			OSCdef(\routines_debug_monitor).free;
		});

		"".postln;
		"╔══════════════════════════════════════════════════════════════════╗".postln;
		"║  OSC PORT INFO - IMPORTANT FOR METRONOME CONNECTION              ║".postln;
		"╠══════════════════════════════════════════════════════════════════╣".postln;
		"║  This SuperCollider instance is listening on PORT: %          ║".format(NetAddr.langPort.asString.padRight(5)).postln;
		"║                                                                  ║".postln;
		"║  If metronome runs in a DIFFERENT SuperCollider instance,        ║".postln;
		"║  update the metronome's OSC port to: %                        ║".format(NetAddr.langPort.asString.padRight(5)).postln;
		"║                                                                  ║".postln;
		"║  OR: Run both routines.scd and metronome.scd in the SAME         ║".postln;
		"║      SuperCollider instance (both will use port 57120)           ║".postln;
		"╚══════════════════════════════════════════════════════════════════╝".postln;
		"".postln;
		"=== Routines Ready ===".postln;
		"".postln;
		"Preset: %".format(presetPath.basename).postln;
		"Inputs: %".format(inputs.size).postln;
		"Outputs: %".format(outputs.size).postln;
		"FX Chains: %".format(fxChains.size).postln;
		"Buffers in dictionary: %".format(~bufferDict.size).postln;
		"".postln;
		"Listening for OSC messages from metronome.scd at /metronome".postln;
		"To cleanup and stop: ~cleanup.value".postln;
		"".postln;
	});
});
)
