// Routines Configuration GUI
// Standalone tool for creating and editing preset files
// No audio server required - pure configuration interface
//
// Scans inputs/ and outputs/ folders for routine files with @meta blocks
// Saves presets to .preset files that can be loaded by routines.scd

(
// =============================================================================
// VARIABLE DECLARATIONS
// =============================================================================

var inputs, outputs, synthdefs, preloadBuffers, audioInputBus, fxChains;
var mainWindow, processListView, bufferListView, routingListView, paramEditorView, listStack;
// inputListView / outputListView kept as ghost variables for backward-compat refresh functions
var inputListView, outputListView;
var processTabButton, bufferTabButton, routingTabButton, currentTab;
// processItems: Array of (role: \input|\output, idx: Integer) for each row in processListView
var processItems;
var selectedInstance, selectedInstanceType, isEditMode;
var paramWidgets, currentPresetPath, hasUnsavedChanges;
var statusBarText, presetsPath, basePath;

// =============================================================================
// INITIALIZATION
// =============================================================================

inputs = [];
outputs = [];
synthdefs = [];
preloadBuffers = [];
fxChains = [];
audioInputBus = 0;
processItems = [];
currentTab = \process;
selectedInstance = nil;
selectedInstanceType = nil;
isEditMode = false;
paramWidgets = IdentityDictionary.new;
currentPresetPath = nil;
hasUnsavedChanges = false;

// Set paths relative to this script
basePath = PathName(thisProcess.nowExecutingPath).pathOnly;
presetsPath = basePath +/+ "presets";

"=== Routines Configuration GUI ===".postln;
"No audio server needed - configuration only".postln;

// =============================================================================
// ROUTINE SCANNER AND METADATA FUNCTIONS
// =============================================================================

~inputTypes = Dictionary.new;
~outputTypes = Dictionary.new;

// Parse @meta block from a routine file
~parseMetadata = { |filePath|
	var file, content, metaStart, metaEnd, metaBlock, metaDict, lines;
	metaDict = nil;

	try {
		file = File(filePath, "r");
		if(file.isOpen, {
			content = file.readAllString;
			file.close;

			// Find @meta: block
			metaStart = content.find("// @meta:");
			if(metaStart.notNil, {
				// Extract metadata block (find closing paren with comment marker)
				metaEnd = content.find("// )", metaStart);
				if(metaEnd.notNil, {
					// Get the full metadata block including the closing paren
					metaBlock = content.copyRange(metaStart, metaEnd + 3);

					// Remove comment markers from each line
					lines = metaBlock.split($\n).collect({ |line|
						var stripped;
						stripped = line.stripWhiteSpace;
						if(stripped.size >= 2 && (stripped[0] == $/) && (stripped[1] == $/), {
							stripped = stripped.copyRange(2, stripped.size - 1).stripWhiteSpace;
						});
						stripped;
					}).select({ |line| line.size > 0 });

					// Join lines with space to create valid SC code
					metaBlock = lines.join(" ");

					// Remove @meta: prefix
					metaBlock = metaBlock.replace("@meta:", "").stripWhiteSpace;

					// Parse as SC dictionary
					try {
						metaDict = metaBlock.interpret;
						if(metaDict.isNil, {
							"Warning: Failed to parse metadata in %".format(PathName(filePath).fileName).postln;
						});
					} { |error|
						"Warning: Syntax error in metadata for %: %".format(PathName(filePath).fileName, error).postln;
					};
				});
			});
		});
	} { |error|
		"Error reading file %: %".format(filePath, error).postln;
	};

	metaDict;
};

// Scan inputs/ and outputs/ folders for routine files
~scanRoutineFolders = {
	var inputPath, outputPath, inputFiles, outputFiles;

	inputPath = basePath +/+ "inputs";
	outputPath = basePath +/+ "outputs";

	"Scanning routine files...".postln;
	"  Input path: %".format(inputPath).postln;
	"  Output path: %".format(outputPath).postln;

	~inputTypes.clear;
	~outputTypes.clear;

	// Scan input routines
	if(PathName(inputPath).isFolder, {
		inputFiles = PathName(inputPath).files.select({ |p| p.extension == "scd" });
		inputFiles.do({ |pathName|
			var metadata;
			metadata = ~parseMetadata.value(pathName.fullPath);
			if(metadata.notNil, {
				if(metadata[\name].notNil, {
					~inputTypes[metadata[\name].asSymbol] = metadata;
					"  Loaded input type: %".format(metadata[\name]).postln;
				}, {
					"  Skipped % (no valid metadata)".format(pathName.fileName).postln;
				});
			}, {
				"  Skipped % (no valid metadata)".format(pathName.fileName).postln;
			});
		});
	}, {
		"Warning: Input path not found: %".format(inputPath).postln;
	});

	// Scan output routines
	if(PathName(outputPath).isFolder, {
		outputFiles = PathName(outputPath).files.select({ |p| p.extension == "scd" });
		outputFiles.do({ |pathName|
			var metadata;
			metadata = ~parseMetadata.value(pathName.fullPath);
			if(metadata.notNil, {
				if(metadata[\name].notNil, {
					~outputTypes[metadata[\name].asSymbol] = metadata;
					"  Loaded output type: %".format(metadata[\name]).postln;
				}, {
					"  Skipped % (no valid metadata)".format(pathName.fileName).postln;
				});
			}, {
				"  Skipped % (no valid metadata)".format(pathName.fileName).postln;
			});
		});
	}, {
		"Warning: Output path not found: %".format(outputPath).postln;
	});

	"Found % input types, % output types".format(~inputTypes.size, ~outputTypes.size).postln;
};

// Scan on initialization
~scanRoutineFolders.value;

// =============================================================================
// SYNTHDEF SCANNER
// =============================================================================

~availableSynthdefs = [];
~availableFxSynthdefs = [];  // SynthDefs suitable for FX stages (must expose inBus + outBus)
~synthdefMeta = IdentityDictionary.new;
~synthdefFileNames = IdentityDictionary.new;  // synthDef symbol -> "filename.scd"

// Scan synthdefs/ folder and extract SynthDef names from SynthDef(\name, declarations
// Also parses @meta blocks (same format as inputs/outputs) and stores in ~synthdefMeta
~scanSynthdefs = {
	var synthdefPath, filePaths;
	synthdefPath = basePath +/+ "synthdefs";
	~availableSynthdefs = [];
	~availableFxSynthdefs = [];
	~synthdefMeta = IdentityDictionary.new;
	~synthdefFileNames = IdentityDictionary.new;

	// Use pathMatch glob to find all .scd files
	filePaths = (synthdefPath +/+ "*.scd").pathMatch;

	if(filePaths.size > 0, {
		filePaths.do({ |fullPath|
			var file, content, searchStr, nameStart, nameEnd, name, meta;
			try {
				file = File(fullPath, "r");
				if(file.isOpen, {
					content = file.readAllString;
					file.close;
					// Search for SynthDef(\name, or SynthDef('name',
					// String.find(pattern, ignoreCase, offset) -- must pass offset as 3rd arg
					searchStr = "SynthDef(\\";
					nameStart = content.find(searchStr);
					if(nameStart.notNil, {
						nameStart = nameStart + searchStr.size;
						// find "," starting from nameStart (ignoreCase: false, offset: nameStart)
						nameEnd = content.find(",", false, nameStart);
						if(nameEnd.notNil, {
							name = content.copyRange(nameStart, nameEnd - 1).stripWhiteSpace;
							if(name.size > 0, {
								~availableSynthdefs = ~availableSynthdefs.add(name.asSymbol);
								~synthdefFileNames[name.asSymbol] = PathName(fullPath).fileName;
								// FX-stage compatibility heuristic:
								// A SynthDef used in Routing / SynthDef Direct should expose both
								// inBus and outBus controls so it can process chain audio in-place.
								if(content.contains("inBus") && content.contains("outBus"), {
									~availableFxSynthdefs = ~availableFxSynthdefs.add(name.asSymbol);
								});
								"  Synthdef found: %".format(name).postln;
							});
						});
					}, {
						// Try quoted symbol form: SynthDef('name',
						searchStr = "SynthDef('";
						nameStart = content.find(searchStr);
						if(nameStart.notNil, {
							nameStart = nameStart + searchStr.size;
							nameEnd = content.find("'", false, nameStart);
							if(nameEnd.notNil, {
								name = content.copyRange(nameStart, nameEnd - 1).stripWhiteSpace;
								if(name.size > 0, {
									~availableSynthdefs = ~availableSynthdefs.add(name.asSymbol);
									~synthdefFileNames[name.asSymbol] = PathName(fullPath).fileName;
									if(content.contains("inBus") && content.contains("outBus"), {
										~availableFxSynthdefs = ~availableFxSynthdefs.add(name.asSymbol);
									});
									"  Synthdef found: %".format(name).postln;
								});
							});
						});
					});

					// Also parse @meta block if present
					if(name.notNil && (name.size > 0), {
						meta = ~parseMetadata.value(fullPath);
						if(meta.notNil, {
							~synthdefMeta[name.asSymbol] = meta;
							"  Synthdef meta loaded: % (% params)".format(
								name,
								(meta[\parameters] ? []).size
							).postln;
						});
					});
				}, {
					"Warning: could not open %".format(fullPath).postln;
				});
			} { |err|
				"Error scanning %: %".format(fullPath, err.messageString).postln;
			};
		});
	}, {
		"Warning: no .scd files found in synthdefs path: %".format(synthdefPath).postln;
	});

	"Synthdefs scanned: % found, % FX-compatible, % with metadata".format(
		~availableSynthdefs.size, ~availableFxSynthdefs.size, ~synthdefMeta.size
	).postln;
};

~scanSynthdefs.value;

// Execute routines.scd (same folder as this GUI). Requires a booted audio server
// if the preset loads SynthDefs/buffers; post errors to the post window.
~reloadRoutines = {
	var routinesPath;
	routinesPath = (basePath +/+ "routines.scd").standardizePath;
	if(File.exists(routinesPath).not, {
		"[GUI] routines.scd not found: %".format(routinesPath).postln;
	}, {
		if(hasUnsavedChanges, {
			"[GUI] Reload routines: you have unsaved preset changes — save first if needed.".postln;
		});
		"[GUI] Executing % ...".format(routinesPath).postln;
		try {
			thisProcess.interpreter.executeFile(routinesPath);
			"[GUI] routines.scd finished (check post window for controller output).".postln;
		} { |err|
			"[GUI] Error executing routines.scd:".postln;
			err.postln;
		};
	});
};

// =============================================================================
// VALIDATION FUNCTIONS
// =============================================================================

~validateInstance = { |instance, instanceType|
	var errors, id;
	errors = [];
	id = instance[\id];

	// Check ID exists
	if(id.isNil || (id.asString.size == 0), {
		errors = errors.add("ID is required");
	});

	// Check for duplicate IDs
	if(instanceType == \input, {
		inputs.do { |inp|
			var isDuplicate;
			isDuplicate = if(isEditMode && selectedInstance.notNil, {
				(inp[\id] == id) && (selectedInstance[\id] != id)
			}, {
				inp[\id] == id
			});
			if(isDuplicate, { errors = errors.add("Duplicate input ID: " ++ id); });
		};
	}, {
		outputs.do { |out|
			var isDuplicate;
			isDuplicate = if(isEditMode && selectedInstance.notNil, {
				(out[\id] == id) && (selectedInstance[\id] != id)
			}, {
				out[\id] == id
			});
			if(isDuplicate, { errors = errors.add("Duplicate output ID: " ++ id); });
		};
	});

	// Validate input-specific fields
	if(instanceType == \input, {
		var startBar, startBeat, durationBeats;
		startBar = instance[\startBar];
		startBeat = instance[\startBeat];
		durationBeats = instance[\durationBeats];

		if(startBar.isNil || startBeat.isNil || durationBeats.isNil, {
			errors = errors.add("Start Bar, Start Beat, and Duration are required");
		}, {
			if(startBar.isNumber && startBeat.isNumber && durationBeats.isNumber, {
				if(startBar < 1, { errors = errors.add("Start Bar must be >= 1"); });
				if(startBeat < 1, { errors = errors.add("Start Beat must be >= 1"); });
				if(durationBeats < 1, { errors = errors.add("Duration must be at least 1 beat"); });
			}, {
				errors = errors.add("Bar, Beat, and Duration values must be numbers");
			});
		});
	}, {
		// Validate output-specific fields
		if(instance[\bar].isNil || instance[\beat].isNil, {
			errors = errors.add("Bar and Beat are required");
		}, {
			if(instance[\bar].isNumber.not || instance[\beat].isNumber.not, {
				errors = errors.add("Bar and Beat values must be numbers");
			}, {
				if(instance[\bar] < 1, { errors = errors.add("Bar must be >= 1"); });
				if(instance[\beat] < 1, { errors = errors.add("Beat must be >= 1"); });
			});
		});

		// Verify source exists (only if source is specified)
		// Note: Some output routines don't need a source (e.g., simple_synth_out)
		if(instance[\source].notNil && (instance[\source] != \none), {
			var sourceExists, isPreloaded;
			sourceExists = inputs.any({ |inp| inp[\id] == instance[\source] });
			isPreloaded = preloadBuffers.any({ |buf| buf[\id] == instance[\source] });

			if(sourceExists.not && isPreloaded.not, {
				// Just warn, don't block - user may add the source later
				"Warning: Source '%' not found (may be added later)".format(instance[\source]).postln;
			});
		});
	});

	errors;
};

// =============================================================================
// INSTANCE MANAGEMENT FUNCTIONS
// =============================================================================

~addInput = { |inputConfig|
	var errors;
	errors = ~validateInstance.value(inputConfig, \input);
	if(errors.size > 0, {
		~showError.value("Validation Error", errors.join("\n"));
		false;
	}, {
		inputs = inputs.add(inputConfig);
		~refreshInputList.value;
		hasUnsavedChanges = true;
		~updateStatusBar.value;
		"Added input: %".format(inputConfig[\id]).postln;
		true;
	});
};

~updateInput = { |oldID, newConfig|
	var idx, errors;
	errors = ~validateInstance.value(newConfig, \input);
	if(errors.size > 0, {
		~showError.value("Validation Error", errors.join("\n"));
		false;
	}, {
		idx = inputs.detectIndex({ |inp| inp[\id] == oldID });
		if(idx.notNil, {
			inputs[idx] = newConfig;
			~refreshInputList.value;
			hasUnsavedChanges = true;
			~updateStatusBar.value;
			true;
		}, { false; });
	});
};

~removeInput = { |inputID|
	var usedByOutputs, usedByChains;
	usedByOutputs = outputs.select({ |out| out[\source] == inputID });
	// Check new fxStages format: any stage with mode=instance and fx=inputID
	usedByChains = fxChains.select({ |ch|
		var norm = ~normalizeChain.value(ch);
		(norm[\fxStages] ? []).any({ |stage|
			(stage[\mode] == \instance) && (stage[\fx] == inputID);
		});
	});
	if(usedByOutputs.size > 0, {
		var outputIDs = usedByOutputs.collect({ |out| out[\id] }).join(", ");
		~showError.value("Cannot Remove", "Input used by outputs: " ++ outputIDs);
		false;
	}, {
		if(usedByChains.size > 0, {
			~showError.value("Cannot Remove", "Input used in FX chain routing");
			false;
		}, {
			inputs = inputs.reject({ |inp| inp[\id] == inputID });
			~refreshInputList.value;
			hasUnsavedChanges = true;
			~updateStatusBar.value;
			true;
		});
	});
};

~addOutput = { |outputConfig|
	var errors;
	errors = ~validateInstance.value(outputConfig, \output);
	if(errors.size > 0, {
		~showError.value("Validation Error", errors.join("\n"));
		false;
	}, {
		outputs = outputs.add(outputConfig);
		~refreshOutputList.value;
		hasUnsavedChanges = true;
		~updateStatusBar.value;
		true;
	});
};

~updateOutput = { |oldID, newConfig|
	var idx, errors;
	errors = ~validateInstance.value(newConfig, \output);
	if(errors.size > 0, {
		~showError.value("Validation Error", errors.join("\n"));
		false;
	}, {
		idx = outputs.detectIndex({ |out| out[\id] == oldID });
		if(idx.notNil, {
			outputs[idx] = newConfig;
			~refreshOutputList.value;
			hasUnsavedChanges = true;
			~updateStatusBar.value;
			true;
		}, { false; });
	});
};

~removeOutput = { |outputID|
	var usedByChains;
	usedByChains = fxChains.select({ |ch| ch[\source] == outputID });
	if(usedByChains.size > 0, {
		~showError.value("Cannot Remove", "Output used in FX chain routing");
		false;
	}, {
		outputs = outputs.reject({ |out| out[\id] == outputID });
		~refreshOutputList.value;
		hasUnsavedChanges = true;
		~updateStatusBar.value;
		true;
	});
};

~duplicateInput = { |inputID|
	var original, duplicate, newID, counter;
	original = inputs.detect({ |inp| inp[\id] == inputID });
	if(original.notNil, {
		counter = 1;
		newID = (original[\id].asString ++ "_copy").asSymbol;
		while({ inputs.any({ |inp| inp[\id] == newID }) }, {
			counter = counter + 1;
			newID = (original[\id].asString ++ "_copy" ++ counter).asSymbol;
		});
		duplicate = original.copy;
		duplicate[\id] = newID;
		~addInput.value(duplicate);
	});
};

~duplicateOutput = { |outputID|
	var original, duplicate, newID, counter;
	original = outputs.detect({ |out| out[\id] == outputID });
	if(original.notNil, {
		counter = 1;
		newID = (original[\id].asString ++ "_copy").asSymbol;
		while({ outputs.any({ |out| out[\id] == newID }) }, {
			counter = counter + 1;
			newID = (original[\id].asString ++ "_copy" ++ counter).asSymbol;
		});
		duplicate = original.copy;
		duplicate[\id] = newID;
		~addOutput.value(duplicate);
	});
};

// =============================================================================
// BUFFER MANAGEMENT
// =============================================================================

~addBuffer = { |bufferConfig|
	var id, path, errors;
	errors = [];
	id = bufferConfig[\id];
	path = bufferConfig[\path];

	// Validate ID
	if(id.isNil || (id.asString.size == 0), {
		errors = errors.add("ID is required");
	});

	// Check for duplicate IDs (in buffers, inputs, and outputs)
	if(preloadBuffers.any({ |buf| buf[\id] == id }), {
		errors = errors.add("Duplicate buffer ID: " ++ id);
	});
	if(inputs.any({ |inp| inp[\id] == id }), {
		errors = errors.add("ID already used by input: " ++ id);
	});

	// Validate path
	if(path.isNil || (path.asString.size == 0), {
		errors = errors.add("File path is required");
	}, {
		if(File.exists(path).not, {
			errors = errors.add("File not found: " ++ path);
		});
	});

	if(errors.size > 0, {
		~showError.value("Validation Error", errors.join("\n"));
		false;
	}, {
		preloadBuffers = preloadBuffers.add(bufferConfig);
		~refreshBufferList.value;
		hasUnsavedChanges = true;
		~updateStatusBar.value;
		"Added buffer: % -> %".format(id, PathName(path).fileName).postln;
		true;
	});
};

~removeBuffer = { |bufferID|
	var usedByOutputs;
	usedByOutputs = outputs.select({ |out| out[\source] == bufferID });
	if(usedByOutputs.size > 0, {
		var outputIDs = usedByOutputs.collect({ |out| out[\id] }).join(", ");
		~showError.value("Cannot Remove", "Buffer used by outputs: " ++ outputIDs);
		false;
	}, {
		preloadBuffers = preloadBuffers.reject({ |buf| buf[\id] == bufferID });
		~refreshBufferList.value;
		hasUnsavedChanges = true;
		~updateStatusBar.value;
		"Removed buffer: %".format(bufferID).postln;
		true;
	});
};

~refreshBufferList = {
	var items;
	items = preloadBuffers.collect { |buf|
		"% | %".format(buf[\id], PathName(buf[\path]).fileName);
	};
	{ bufferListView.items = items; }.defer;
};

~showAddBufferDialog = {
	FileDialog({ |paths|
		if(paths.notNil && paths.size > 0, {
			var path, fileName, defaultID;
			path = paths[0];
			fileName = PathName(path).fileNameWithoutExtension;

			// Generate default ID: remove non-alphanumeric chars
			defaultID = fileName.select({ |char| char.isAlphaNum });
			if(defaultID.isEmpty, { defaultID = "buf" });

			// Show dialog to confirm/edit ID
			{
				var dialog, idField;
				dialog = Window("Add Buffer", Rect(400, 400, 400, 150)).front;
				dialog.layout = VLayout(
					HLayout(
						StaticText().string_("File:").align_(\right).minWidth_(50),
						StaticText().string_(PathName(path).fileName).minWidth_(300)
					),
					HLayout(
						StaticText().string_("ID:").align_(\right).minWidth_(50),
						idField = TextField().string_(defaultID).minWidth_(300)
					),
					HLayout(
						nil,
						Button().states_([["Cancel"]]).minWidth_(80)
							.action_({ dialog.close; }),
						Button().states_([["Add", Color.white, Color.green(0.6)]]).minWidth_(80)
							.action_({
								var id = idField.string.asSymbol;
								dialog.close;
								~addBuffer.value((id: id, path: path));
							})
					)
				).margins_(15);
			}.defer;
		});
	}, fileMode: 1, acceptMode: 0);
};

// =============================================================================
// ROUTING (FX CHAIN) MANAGEMENT
// =============================================================================

// Normalize a loaded chain into the new fxStages format if it uses the old format.
// Old: (\source: x, \fxSynthDef: foo, \fxArgs: (), \fxOutBus: 0)
//      (\source: x, \fx: inputID)
// New: (\source: x, \fxStages: [...], \fxOutBus: 0)
~normalizeChain = { |chain|
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

// Build a human-readable summary string for a chain (for the routing list view).
// e.g. "bufout2 > violinResSynth > reverbSynth > out:0"
~chainSummary = { |chain|
	var norm = ~normalizeChain.value(chain);
	var stages = norm[\fxStages] ? [];
	var fxOutBus = norm[\fxOutBus] ? 0;
	var parts = [norm[\source].asString];
	stages.do { |stage|
		var mode = stage[\mode] ? \synthdef;
		if(mode == \instance, {
			parts = parts.add(stage[\fx].asString ++ " [inst]");
		}, {
			parts = parts.add(stage[\synthDef].asString);
		});
	};
	parts = parts.add("out:" ++ fxOutBus.asString);
	parts.join(" > ");
};

// Add a multi-stage chain. fxStages is an Array of stage Events.
~addRoutingChain = { |sourceID, fxStages, fxOutBus|
	var errors = [], chain;

	if(sourceID.isNil || (sourceID == \none), {
		errors = errors.add("Source (output) is required");
	});
	if(fxStages.isNil || (fxStages.size == 0), {
		errors = errors.add("At least one FX stage is required");
	});

	if(errors.size > 0, {
		~showError.value("Validation Error", errors.join("\n"));
		false;
	}, {
		chain = (\source: sourceID, \fxStages: fxStages, \fxOutBus: fxOutBus ? 0);
		fxChains = fxChains.add(chain);
		~refreshRoutingList.value;
		hasUnsavedChanges = true;
		~updateStatusBar.value;
		"Added chain: %".format(~chainSummary.value(chain)).postln;
		true;
	});
};

// Keep legacy helpers for backward compat (they delegate to ~addRoutingChain)
~addRoutingInstance = { |sourceID, fxID|
	~addRoutingChain.value(
		sourceID,
		[(\mode: \instance, \fx: fxID)],
		0
	);
};

~addRoutingSynthDef = { |sourceID, synthDefName, fxOutBus, fxArgs|
	~addRoutingChain.value(
		sourceID,
		[(\mode: \synthdef, \synthDef: synthDefName, \args: fxArgs ? ())],
		fxOutBus ? 0
	);
};

~updateRouting = { |index, newChain|
	fxChains[index] = newChain;
	~refreshRoutingList.value;
	hasUnsavedChanges = true;
	~updateStatusBar.value;
	"Updated FX chain at index %".format(index).postln;
};

~removeRouting = { |index|
	if(index >= 0 && (index < fxChains.size), {
		fxChains = fxChains.reject({ |ch, i| i == index });
		~refreshRoutingList.value;
		hasUnsavedChanges = true;
		~updateStatusBar.value;
		"Removed FX chain at index %".format(index).postln;
		true;
	}, { false; });
};

~refreshRoutingList = {
	var items;
	items = fxChains.collect { |ch| ~chainSummary.value(ch); };
	{ routingListView.items = items; }.defer;
};

// Rebuild the per-SynthDef parameter section for a given stage index.
// stageIdx is used to namespace widget keys so multiple stages don't collide.
// Called when the SynthDef selection changes or when the FX section is first built.
~rebuildSynthDefParams = { |paramContainer, synthName, existingArgs, stageIdx|
	var prefix = "fxParam_s" ++ stageIdx ++ "_";
	var sectionKey = ("fxParamSectionView_s" ++ stageIdx).asSymbol;

	// Remove previously built param widgets for this stage
	paramWidgets.keys.asArray.do { |key|
		if(key.asString.beginsWith(prefix), {
			paramWidgets.removeAt(key);
		});
	};
	if(paramWidgets[sectionKey].notNil, {
		paramWidgets[sectionKey].remove;
		paramWidgets[sectionKey] = nil;
	});
	// Keep legacy single-stage key removal for safety
	if(stageIdx == 0, {
		paramWidgets.keys.asArray.do { |key|
			if(key.asString.beginsWith("fxParam_") && (key.asString.beginsWith(prefix).not), {
				paramWidgets.removeAt(key);
			});
		};
		if(paramWidgets[\fxParamSectionView].notNil, {
			paramWidgets[\fxParamSectionView].remove;
			paramWidgets[\fxParamSectionView] = nil;
		});
	});

	paramWidgets[sectionKey] = View(paramContainer)
		.layout_(VLayout().margins_(0).spacing_(3));

	{
		var meta, parameters, paramView;
		paramView = paramWidgets[sectionKey];
		meta = if(synthName.notNil, { ~synthdefMeta[synthName.asSymbol] }, { nil });
		parameters = if(meta.notNil, { meta[\parameters] ? [] }, { [] });

		if(parameters.size > 0, {
			StaticText(paramView)
				.string_("Parameters")
				.font_(Font.default.bold_(true))
				.minHeight_(22);

			parameters.do { |param|
				var paramName, paramType, defaultVal, currentVal, label, row;
				var widgetKey, labelKey;
				paramName  = param[\name].asSymbol;
				paramType  = param[\type].asSymbol;
				label      = param[\label] ? param[\name];
				defaultVal = param[\default];
				currentVal = if(existingArgs.notNil, {
					existingArgs[paramName] ? defaultVal
				}, { defaultVal });

				widgetKey = (prefix ++ paramName).asSymbol;
				labelKey  = (prefix ++ paramName ++ "Label").asSymbol;

				row = View(paramView).layout_(HLayout().margins_(0).spacing_(5));
				StaticText(row, 150@25).string_(label ++ ":").align_(\right);

			case
			{ paramType == \int } {
				var min, max;
				min = param[\min] ? 1;
				max = param[\max] ? 100;
				paramWidgets[widgetKey] = NumberBox(row, 120@25)
					.value_(currentVal.asInteger)
					.decimals_(0)
					.clipLo_(min)
					.clipHi_(max);
			}
			{ paramType == \float } {
				paramWidgets[widgetKey] = NumberBox(row, 120@25)
					.value_(currentVal)
					.clipLo_(param[\min] ? -1e38)
					.clipHi_(param[\max] ? 1e38);
			}
			{ paramType == \choice } {
					var options, selectedIdx;
					options = param[\options] ? [];
					selectedIdx = options.collect(_.asSymbol).indexOf(currentVal.asSymbol) ? 0;
					paramWidgets[widgetKey] = PopUpMenu(row, 200@25)
						.items_(options)
						.value_(selectedIdx);
				}
				{ paramType == \bool } {
					paramWidgets[widgetKey] =
						CheckBox(row, 25@25).value_(currentVal.asBoolean);
				}
				{ // default
					paramWidgets[widgetKey] =
						NumberBox(row, 100@25).value_(currentVal ? 0);
				};
			};
		}, {
			// No metadata: fall back to free-text FX Args field
			var row;
			var argsKey = (prefix ++ "fxArgs").asSymbol;
			row = View(paramView).layout_(HLayout().margins_(0).spacing_(5));
			StaticText(row, 150@25).string_("FX Args:").align_(\right);
			paramWidgets[argsKey] = TextField(row, 200@25)
				.string_(if(existingArgs.notNil, { ~fxArgsToString.value(existingArgs) }, { "" }))
				.background_(Color.white);
			StaticText(row).string_("optional").font_(Font.default.size_(10));

			row = View(paramView).layout_(HLayout().margins_(0).spacing_(5));
			StaticText(row, 150@25);
			StaticText(row, 200@25)
				.string_("e.g.  length: 0.75, bodyFreq: 500")
				.font_(Font.default.size_(10))
				.stringColor_(Color.gray(0.5));
		});
	}.defer;
};

// Collect FX parameter values for a given stage index.
// Returns an Event suitable for use as stage[\args] in the preset.
~collectFxParameters = { |synthDefName, stageIdx|
	var config = (), meta, parameters;
	var prefix = "fxParam_s" ++ stageIdx ++ "_";
	meta = if(synthDefName.notNil, { ~synthdefMeta[synthDefName.asSymbol] }, { nil });
	parameters = if(meta.notNil, { meta[\parameters] ? [] }, { [] });

	if(parameters.size > 0, {
		parameters.do { |param|
			var paramName, paramType, widget, value;
			paramName = param[\name].asSymbol;
			paramType = param[\type].asSymbol;
			widget = paramWidgets[(prefix ++ paramName).asSymbol];

		if(widget.notNil, {
			case
			{ paramType == \int } {
				value = widget.value.round(1).asInteger;
			}
			{ paramType == \float } {
				value = widget.value;
			}
			{ paramType == \choice } {
				var options = param[\options] ? [];
				value = if(options.size > 0, { options[widget.value].asSymbol }, { nil });
			}
			{ paramType == \bool } {
				value = widget.value.asBoolean;
			}
			{ value = widget.value; };

			if(value.notNil, { config[paramName] = value; });
		});
		};
	}, {
		// No @meta: fall back to free-text TextField for this stage
		var argsKey = (prefix ++ "fxArgs").asSymbol;
		var fxArgsStr = if(paramWidgets[argsKey].notNil, {
			paramWidgets[argsKey].string;
		}, { "" });
		if(fxArgsStr.notNil && (fxArgsStr.stripWhiteSpace.size > 0), {
			try {
				var parsed = ("(" ++ fxArgsStr ++ ")").interpret;
				if(parsed.notNil && parsed.isKindOf(Event), {
					config = parsed;
				});
			} { |err|
				"Warning: could not parse FX args (stage %): %".format(stageIdx, err.messageString).postln;
			};
		});
	});

	config;
};

// =============================================================================
// MULTI-STAGE FX SECTION BUILDER
// =============================================================================
//
// ~stageDataList is the live working copy of the stages being edited.
// Each entry: (\mode: \synthdef|\instance, \synthDef: sym, \args: event, \fx: sym)
// It is rebuilt whenever a stage is added, removed, or reordered.

~stageDataList = [];

// Build a single stage panel inside stageContainer at position stageIdx.
// existingStage: Event with pre-fill data (or nil for a blank stage).
// isFirstStage: Boolean - only the first stage may use Input Instance mode.
~buildStagePanel = { |stageContainer, stageIdx, existingStage, isFirstStage, rebuildAllFunc|
	var panelView, headerRow, bodyView, modeMenu, initialMode;
	var existingMode = if(existingStage.notNil, { existingStage[\mode] ? \synthdef }, { \synthdef });

	// 0 = SynthDef Direct, 1 = Input Instance (only allowed for stage 0)
	initialMode = if(existingMode == \instance, { 1 }, { 0 });

	panelView = View(stageContainer)
		.background_(Color.gray(0.92))
		.layout_(VLayout().margins_(6).spacing_(4));

	// --- Header row: stage label + Up / Down / Remove ---
	headerRow = View(panelView).layout_(HLayout().margins_(0).spacing_(4));
	StaticText(headerRow)
		.string_("Stage " ++ (stageIdx + 1))
		.font_(Font.default.bold_(true))
		.minHeight_(22);
	View(headerRow); // spacer

	// Up button (disabled for stage 0)
	Button(headerRow).minWidth_(28).fixedHeight_(22)
		.states_([["▲", Color.black, Color.gray(0.8)]])
		.enabled_(stageIdx > 0)
		.action_({
			var tmp = ~stageDataList[stageIdx - 1];
			~stageDataList[stageIdx - 1] = ~stageDataList[stageIdx];
			~stageDataList[stageIdx]     = tmp;
			rebuildAllFunc.value;
		});

	// Down button (disabled for last stage)
	Button(headerRow).minWidth_(28).fixedHeight_(22)
		.states_([["▼", Color.black, Color.gray(0.8)]])
		.enabled_(stageIdx < (~stageDataList.size - 1))
		.action_({
			var tmp = ~stageDataList[stageIdx + 1];
			~stageDataList[stageIdx + 1] = ~stageDataList[stageIdx];
			~stageDataList[stageIdx]     = tmp;
			rebuildAllFunc.value;
		});

	// Remove button
	Button(headerRow).minWidth_(28).fixedHeight_(22)
		.states_([["✕", Color.white, Color.red(0.6)]])
		.action_({
			~stageDataList = ~stageDataList.reject({ |s, i| i == stageIdx });
			rebuildAllFunc.value;
		});

	// --- Mode selector (Input Instance only for stage 0) ---
	bodyView = View(panelView).layout_(VLayout().margins_(0).spacing_(3));

	{
		var modeRow, modeItems;
		modeRow = View(bodyView).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(modeRow, 120@22).string_("Mode:").align_(\right);

		modeItems = if(isFirstStage, {
			["SynthDef Direct", "Input Instance"];
		}, {
			["SynthDef Direct"];
		});

		modeMenu = PopUpMenu(modeRow, 220@22)
			.items_(modeItems)
			.value_(if(isFirstStage, { initialMode }, { 0 }));

		paramWidgets[("stageMode_" ++ stageIdx).asSymbol] = modeMenu;

		// Build the mode-specific sub-section
		~buildStageModeSection.value(bodyView, stageIdx, modeMenu.value, existingStage, isFirstStage);

		modeMenu.action_({ |menu|
			// Save current synthdef selection before rebuild
			~buildStageModeSection.value(bodyView, stageIdx, menu.value, nil, isFirstStage);
		});
	}.defer;
};

// Build the mode-specific content inside a stage body view.
// Called initially and when the mode menu changes.
~buildStageModeSection = { |bodyView, stageIdx, modeValue, existingStage, isFirstStage|
	var sectionKey = ("stageModeSection_" ++ stageIdx).asSymbol;

	// Remove previous mode section
	if(paramWidgets[sectionKey].notNil, {
		paramWidgets[sectionKey].remove;
		paramWidgets[sectionKey] = nil;
	});

	paramWidgets[sectionKey] = View(bodyView).layout_(VLayout().margins_(0).spacing_(3));

	{
		var modeView = paramWidgets[sectionKey];

		if(isFirstStage && (modeValue == 1), {
			// --- Input Instance mode (first stage only) ---
			var fxIDs = [], fxLabels = [], row, selectedIdx = 0;
			inputs.do({ |inp|
				fxIDs = fxIDs.add(inp[\id]);
				fxLabels = fxLabels.add("% (%)".format(inp[\id], inp[\type]));
			});
			if(fxIDs.size == 0, {
				fxIDs = [\none];
				fxLabels = ["(no inputs defined)"];
			});
			paramWidgets[("stageFxIDs_" ++ stageIdx).asSymbol] = fxIDs;

			if(existingStage.notNil, {
				var found = fxIDs.indexOf(existingStage[\fx]);
				if(found.notNil, { selectedIdx = found; });
			});

			row = View(modeView).layout_(HLayout().margins_(0).spacing_(5));
			StaticText(row, 120@22).string_("Input Instance:").align_(\right);
			paramWidgets[("stageFxMenu_" ++ stageIdx).asSymbol] = PopUpMenu(row, 220@22)
				.items_(fxLabels)
				.value_(selectedIdx);
		}, {
			// --- SynthDef Direct mode ---
			var fxSynthdefs, synthdefLabels, initialSynthIdx = 0, initialSynthName = nil;
			var existingArgs = if(existingStage.notNil, { existingStage[\args] }, { nil });
			var row, paramContainer;

			// Keep a placeholder at index 0 so a stage is never auto-bound to the
			// first synthdef accidentally.
			fxSynthdefs = [nil] ++ ~availableFxSynthdefs;
			synthdefLabels = if(~availableFxSynthdefs.size > 0, {
				["(select SynthDef)"] ++ ~availableFxSynthdefs.collect(_.asString);
			}, {
				["(no FX-compatible synthdefs found)"]
			});
			paramWidgets[("stageSynthDefList_" ++ stageIdx).asSymbol] = fxSynthdefs;

			if(existingStage.notNil, {
				if(existingStage[\synthDef].notNil, {
					var found = fxSynthdefs.indexOf(existingStage[\synthDef].asSymbol);
					if(found.notNil, { initialSynthIdx = found; });
				});
			});
			initialSynthName = if(fxSynthdefs.size > 0, {
				fxSynthdefs[initialSynthIdx];
			}, { nil });

			row = View(modeView).layout_(HLayout().margins_(0).spacing_(5));
			StaticText(row, 120@22).string_("SynthDef:").align_(\right);
			paramWidgets[("stageSynthDefMenu_" ++ stageIdx).asSymbol] = PopUpMenu(row, 220@22)
				.items_(synthdefLabels)
				.value_(initialSynthIdx)
				.action_({ |menu|
					var selectedName = if(fxSynthdefs.size > 0, {
						fxSynthdefs[menu.value];
					}, { nil });
					var paramKey = ("stageParamContainer_" ++ stageIdx).asSymbol;
					~rebuildSynthDefParams.value(
						paramWidgets[paramKey],
						selectedName,
						nil,
						stageIdx
					);
				});

			// Parameter container
			paramContainer = View(modeView).layout_(VLayout().margins_(0).spacing_(3));
			paramWidgets[("stageParamContainer_" ++ stageIdx).asSymbol] = paramContainer;

			~rebuildSynthDefParams.value(paramContainer, initialSynthName, existingArgs, stageIdx);
		});
	}.defer;
};

// Rebuild the entire FX stages section inside the routing editor container.
// existingChain: Event (normalized) with pre-fill data, or nil for a new chain.
~rebuildFxSection = { |container, existingChain|
	var fxSectionView, stagesContainer, addStageBtn, outBusRow;
	var norm, initialStages, fxOutBus, rebuildAll;

	// Normalize existing chain to new format
	norm = if(existingChain.notNil, { ~normalizeChain.value(existingChain) }, { nil });
	initialStages = if(norm.notNil, { norm[\fxStages] ? [] }, { [] });
	fxOutBus = if(norm.notNil, { norm[\fxOutBus] ? 0 }, { 0 });

	// Seed the working stage list
	~stageDataList = initialStages.copy;
	if(~stageDataList.size == 0, {
		// Default: one blank SynthDef Direct stage
		~stageDataList = [(\mode: \synthdef, \synthDef: nil, \args: ())];
	});

	// Remove any previously built FX section
	if(paramWidgets[\fxSectionView].notNil, {
		paramWidgets[\fxSectionView].remove;
		paramWidgets[\fxSectionView] = nil;
	});

	paramWidgets[\fxSectionView] = View(container).layout_(VLayout().margins_(0).spacing_(6));
	fxSectionView = paramWidgets[\fxSectionView];

	// --- Stages container (rebuilt on every add/remove/reorder) ---
	stagesContainer = View(fxSectionView).layout_(VLayout().margins_(0).spacing_(6));
	paramWidgets[\stagesContainer] = stagesContainer;

	// Function to rebuild all stage panels (called on add/remove/reorder)
	rebuildAll = {
		{
			paramWidgets[\stagesContainer].removeAll;
			~stageDataList.do { |stage, i|
				~buildStagePanel.value(
					paramWidgets[\stagesContainer],
					i,
					stage,
					(i == 0),
					rebuildAll
				);
			};
		}.defer;
	};
	paramWidgets[\rebuildAllStages] = rebuildAll;

	// Build initial stage panels
	rebuildAll.value;

	// --- Add Stage button ---
	{
		var btnRow = View(fxSectionView).layout_(HLayout().margins_(0).spacing_(5));
		View(btnRow);
		addStageBtn = Button(btnRow).minWidth_(120).fixedHeight_(26)
			.states_([["+ Add Stage", Color.white, Color.blue(0.55)]])
			.action_({
				~stageDataList = ~stageDataList.add((\mode: \synthdef, \synthDef: nil, \args: ()));
				rebuildAll.value;
			});
	}.defer;

	// --- FX Output Bus (applies to the final stage) ---
	{
		var row = View(fxSectionView).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Final Output Bus:").align_(\right);
		paramWidgets[\routeFxOutBus] = NumberBox(row, 60@25)
			.value_(fxOutBus)
			.decimals_(0)
			.clipLo_(0);
		StaticText(row).string_("(hardware out bus for last stage)").font_(Font.default.size_(10));
	}.defer;
};

// Convert an fxArgs Event back to a display string for the TextField
// e.g. (length: 0.75, bodyFreq: 500) -> "length: 0.75, bodyFreq: 500"
~fxArgsToString = { |argsEvent|
	var pairs, result;
	if(argsEvent.isNil || (argsEvent.size == 0), {
		result = "";
	}, {
		pairs = argsEvent.asPairs.clump(2);
		result = pairs.collect({ |pair| "% : %".format(pair[0], pair[1]) }).join(", ");
	});
	result;
};

~buildRoutingEditor = { |editIndex|
	// editIndex: nil = Add mode, integer = Edit mode (pre-fill from fxChains[editIndex])
	{
		var container, row, sourceIDs, sourceLabels;
		var isEdit, existingChain, titleStr, btnLabel;
		paramWidgets = IdentityDictionary.new;
		~stageDataList = [];
		paramEditorView.removeAll;

		isEdit        = editIndex.notNil;
		existingChain = if(isEdit, { ~normalizeChain.value(fxChains[editIndex]) }, { nil });
		titleStr      = if(isEdit, { "Edit FX Chain" }, { "Add FX Chain" });
		btnLabel      = if(isEdit, { "Save Changes" }, { "Add Chain" });

		container = View();
		paramEditorView.layout = VLayout(
			ScrollView().canvas_(container).minHeight_(500)
		).margins_(0);

		container.layout = VLayout().margins_(10).spacing_(5);

		StaticText(container)
			.string_(titleStr)
			.font_(Font.default.size_(16).bold_(true))
			.align_(\center)
			.background_(Color.gray(0.85))
			.minHeight_(30);

		// Source (output) selector
		sourceIDs = [];
		sourceLabels = [];
		outputs.do({ |out|
			sourceIDs = sourceIDs.add(out[\id]);
			sourceLabels = sourceLabels.add("% (%)".format(out[\id], out[\type]));
		});
		if(sourceIDs.size == 0, {
			sourceIDs = [\none];
			sourceLabels = ["(no outputs defined)"];
		});
		paramWidgets[\routeSourceIDs] = sourceIDs;

		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Source (output):").align_(\right);
		paramWidgets[\routeSource] = PopUpMenu(row, 250@25)
			.items_(sourceLabels)
			.value_({
				var idx = 0;
				if(isEdit, {
					var found = sourceIDs.indexOf(existingChain[\source]);
					if(found.notNil, { idx = found });
				});
				idx;
			}.value);

		// Separator
		StaticText(container)
			.string_("FX Stages")
			.font_(Font.default.size_(13).bold_(true))
			.align_(\center)
			.background_(Color.gray(0.88))
			.minHeight_(24);

		// Build multi-stage FX section
		~rebuildFxSection.value(container, existingChain);

		// Buttons
		row = View(container).layout_(HLayout().margins_(0).spacing_(10));
		View(row);
		Button(row).minWidth_(100).fixedHeight_(30)
			.states_([["Cancel"]])
			.action_({
				~clearParameterEditor.value;
			});
		Button(row).minWidth_(100).fixedHeight_(30)
			.states_([[btnLabel, Color.white, Color.green(0.6)]])
			.action_({
				// Collect source
				var srcIdx = paramWidgets[\routeSource].value;
				var srcID  = paramWidgets[\routeSourceIDs][srcIdx];
				var fxOutBus = if(paramWidgets[\routeFxOutBus].notNil, {
					paramWidgets[\routeFxOutBus].value.asInteger
				}, { 0 });
				var collectedStages = [];
				var validationErrors = [];

				// Collect each stage from ~stageDataList using current widget values
				~stageDataList.do { |stageData, i|
					var modeWidget = paramWidgets[("stageMode_" ++ i).asSymbol];
					var modeVal = if(modeWidget.notNil, { modeWidget.value }, { 0 });
					var isInst = (i == 0) && (modeVal == 1);

					if(isInst, {
						// Input Instance stage
						var fxIDsKey = ("stageFxIDs_" ++ i).asSymbol;
						var fxMenuKey = ("stageFxMenu_" ++ i).asSymbol;
						var fxIDs = paramWidgets[fxIDsKey];
						var fxMenu = paramWidgets[fxMenuKey];
						var fxID = if(fxIDs.notNil && fxMenu.notNil, {
							fxIDs[fxMenu.value];
						}, { nil });
						if(fxID.notNil, {
							collectedStages = collectedStages.add((\mode: \instance, \fx: fxID));
						}, {
							validationErrors = validationErrors.add(
								"Stage %: select an Input Instance".format(i + 1)
							);
						});
					}, {
						// SynthDef Direct stage
						var sdListKey = ("stageSynthDefList_" ++ i).asSymbol;
						var sdMenuKey = ("stageSynthDefMenu_" ++ i).asSymbol;
						var sdList = paramWidgets[sdListKey];
						var sdMenu = paramWidgets[sdMenuKey];
						var synthName = if(sdList.notNil && sdMenu.notNil && (sdMenu.value < sdList.size), {
							sdList[sdMenu.value];
						}, { nil });
						if(synthName.isNil, {
							validationErrors = validationErrors.add(
								"Stage %: select an FX SynthDef".format(i + 1)
							);
						}, {
							var fxArgs = ~collectFxParameters.value(synthName, i);
							collectedStages = collectedStages.add(
								(\mode: \synthdef, \synthDef: synthName, \args: fxArgs)
							);
						});
					});
				};

				if(validationErrors.size > 0, {
					~showError.value("Validation Error", validationErrors.join("\n"));
				}, {
				if(collectedStages.size == 0, {
					~showError.value("Validation Error", "At least one FX stage is required");
				}, {
					var newChain = (\source: srcID, \fxStages: collectedStages, \fxOutBus: fxOutBus);
					if(isEdit, {
						~updateRouting.value(editIndex, newChain);
						~clearParameterEditor.value;
					}, {
						if(~addRoutingChain.value(srcID, collectedStages, fxOutBus), {
							~clearParameterEditor.value;
						});
					});
				});
				});
			});

	}.defer;
};

// =============================================================================
// PRESET MANAGEMENT
// =============================================================================

~newPreset = {
	var doReset = {
		inputs = [];
		outputs = [];
		synthdefs = [];
		preloadBuffers = [];
		fxChains = [];
		audioInputBus = 0;
		currentPresetPath = nil;
		hasUnsavedChanges = false;
		~refreshProcessList.value;
		~refreshBufferList.value;
		~refreshRoutingList.value;
		~clearParameterEditor.value;
		~updateStatusBar.value;
	};
	if(hasUnsavedChanges, {
		~confirmAction.value("Discard unsaved changes?", "New Preset", doReset);
	}, {
		doReset.value;
	});
};

// Collect required SynthDefs from all routines used in the preset
~collectRequiredSynthdefs = {
	var requiredSynthdefs = Set.new;
	
	// Collect from inputs
	inputs.do { |inp|
		var metadata = ~inputTypes[inp[\type].asSymbol];
		if(metadata.notNil, {
			if(metadata[\requiredSynthdefs].notNil, {
				metadata[\requiredSynthdefs].do { |sdef|
					requiredSynthdefs.add(sdef.asString);
				};
			});
		});
	};
	
	// Collect from outputs
	outputs.do { |out|
		var metadata = ~outputTypes[out[\type].asSymbol];
		if(metadata.notNil, {
			if(metadata[\requiredSynthdefs].notNil, {
				metadata[\requiredSynthdefs].do { |sdef|
					requiredSynthdefs.add(sdef.asString);
				};
			});
		});
	};

	// Collect SynthDef filenames from fxChains (new fxStages format)
	fxChains.do { |ch|
		var norm = ~normalizeChain.value(ch);
		(norm[\fxStages] ? []).do { |stage|
			if((stage[\mode] ? \synthdef) == \synthdef, {
				if(stage[\synthDef].notNil, {
					var fileName = ~synthdefFileNames[stage[\synthDef].asSymbol];
					if(fileName.notNil, {
						requiredSynthdefs.add(fileName);
					});
				});
			});
		};
	};
	
	requiredSynthdefs.asArray.sort;
};

~savePreset = { |path|
	var data, file, success, collectedSynthdefs;
	success = false;
	
	// Auto-collect required SynthDefs from routines
	collectedSynthdefs = ~collectRequiredSynthdefs.value;
	
	// Merge with manually specified synthdefs (preserve user-added ones)
	synthdefs.do { |sdef|
		if(collectedSynthdefs.includes(sdef.asString).not, {
			collectedSynthdefs = collectedSynthdefs.add(sdef.asString);
		});
	};
	
	"Auto-collected SynthDefs: %".format(collectedSynthdefs).postln;

	data = (
		audioInputBus: audioInputBus,
		synthdefs: collectedSynthdefs,
		preloadBuffers: preloadBuffers,
		inputs: inputs,
		outputs: outputs,
		fxChains: fxChains
	);

	try {
		file = File(path, "w");
		file.write(data.asCompileString);
		file.close;
		currentPresetPath = path;
		hasUnsavedChanges = false;
		~updateStatusBar.value;
		"Preset saved: %".format(path).postln;
		~showInfo.value("Saved", "Preset saved to:\n" ++ path);
		success = true;
	} {
		~showError.value("Save Error", "Failed to save preset");
	};

	success;
};

~loadPreset = { |path|
	var file, content, data;

	try {
		file = File(path, "r");
		if(file.isOpen, {
			content = file.readAllString;
			file.close;
			data = content.interpret;

		if(data.notNil, {
			audioInputBus = data[\audioInputBus] ? 0;
			synthdefs = data[\synthdefs] ? [];
			preloadBuffers = data[\preloadBuffers] ? [];
			inputs = data[\inputs] ? [];
			outputs = data[\outputs] ? [];
			// Normalize old single-stage chains into new fxStages format
			fxChains = (data[\fxChains] ? []).collect { |ch| ~normalizeChain.value(ch) };
			currentPresetPath = path;
			hasUnsavedChanges = false;
			~refreshProcessList.value;
			~refreshBufferList.value;
			~refreshRoutingList.value;
			~clearParameterEditor.value;
			~updateStatusBar.value;
				"Preset loaded: %".format(path).postln;
				~showInfo.value("Loaded", "Preset loaded from:\n" ++ path);
			}, {
				~showError.value("Load Error", "Failed to parse preset file");
			});
		}, {
			~showError.value("Load Error", "Failed to open file");
		});
	} {
		~showError.value("Load Error", "Error loading preset");
	};
};

~savePresetDialog = {
	FileDialog({ |paths|
		if(paths.notNil && paths.size > 0, {
			var path = paths[0];
			if(path.endsWith(".preset").not, { path = path ++ ".preset"; });
			~savePreset.value(path);
		});
	}, fileMode: 1, acceptMode: 1, path: presetsPath);
};

~loadPresetDialog = {
	if(hasUnsavedChanges, {
		~confirmAction.value("Discard unsaved changes?", "Load Preset", {
			FileDialog({ |paths|
				if(paths.notNil && paths.size > 0, {
					~loadPreset.value(paths[0]);
				});
			}, fileMode: 1, acceptMode: 0, path: presetsPath);
		});
	}, {
		FileDialog({ |paths|
			if(paths.notNil && paths.size > 0, {
				~loadPreset.value(paths[0]);
			});
		}, fileMode: 1, acceptMode: 0, path: presetsPath);
	});
};

// =============================================================================
// GUI REFRESH FUNCTIONS
// =============================================================================

// Rebuild the unified process list from current inputs and outputs arrays.
// processItems is kept in sync so action buttons can resolve item role/index.
~refreshProcessList = {
	var items = [];
	processItems = [];

	inputs.do { |inp, i|
		items = items.add("[IN]  % | % | %:% + %b".format(
			inp[\id], inp[\type],
			inp[\startBar], inp[\startBeat],
			inp[\durationBeats]
		));
		processItems = processItems.add((role: \input, idx: i));
	};

	outputs.do { |out, i|
		items = items.add("[OUT] % | % | src:% | %:%".format(
			out[\id], out[\type],
			out[\source] ? "none",
			out[\bar], out[\beat]
		));
		processItems = processItems.add((role: \output, idx: i));
	};

	{ processListView.items = items; }.defer;
};

// Aliases so existing callers (addInput, removeInput, etc.) still work
~refreshInputList  = { ~refreshProcessList.value; };
~refreshOutputList = { ~refreshProcessList.value; };

~updateStatusBar = {
	var text, presetName;
	presetName = if(currentPresetPath.notNil, {
		PathName(currentPresetPath).fileName;
	}, { "<unsaved>" });
	text = "Preset: % | In: % | Out: % | Proc: % | Buf: % | Chains: % | %".format(
		presetName, inputs.size, outputs.size, inputs.size + outputs.size,
		preloadBuffers.size, fxChains.size,
		if(hasUnsavedChanges, { "UNSAVED" }, { "Saved" })
	);
	{ statusBarText.string = text; }.defer;
};

~clearParameterEditor = {
	{
		paramEditorView.removeAll;
		paramEditorView.layout = VLayout(
			StaticText().string_("Select an item or click Add")
				.font_(Font.default.size_(12))
				.align_(\center)
		).margins_(20);
	}.defer;
};

// =============================================================================
// DIALOG HELPERS
// =============================================================================

~showError = { |title, message|
	{
		var window;
		window = Window(title, Rect(400, 400, 400, 150)).front;
		window.layout = VLayout(
			StaticText().string_(message).align_(\center),
			Button().states_([["OK"]]).action_({ window.close; })
		).margins_(20);
	}.defer;
};

~showInfo = { |title, message|
	{
		var window;
		window = Window(title, Rect(400, 400, 400, 150)).front;
		window.layout = VLayout(
			StaticText().string_(message).align_(\center),
			Button().states_([["OK", Color.black, Color.green(0.7)]])
				.action_({ window.close; })
		).margins_(20);
	}.defer;
};

~confirmAction = { |message, title, action|
	{
		var window;
		window = Window(title ? "Confirm", Rect(400, 400, 350, 120)).front;
		window.layout = VLayout(
			StaticText().string_(message).align_(\center),
			HLayout(
				Button().states_([["Yes", Color.black, Color.green(0.7)]])
					.action_({ window.close; action.value; }),
				Button().states_([["No", Color.black, Color.red(0.7)]])
					.action_({ window.close; })
			)
		).margins_(20);
	}.defer;
};

// =============================================================================
// DYNAMIC WIDGET GENERATION
// =============================================================================

~generateParameterWidgets = { |container, metadata, existingData, rebuildFunc|
	var parameters, currentParamValues;
	parameters = metadata[\parameters] ? [];
	currentParamValues = IdentityDictionary.new;

	parameters.do { |param|
		var paramName, paramType, defaultVal, currentVal, label, row, showIf, shouldShow;
		paramName = param[\name].asSymbol;
		paramType = param[\type].asSymbol;
		label = param[\label] ? param[\name];
		defaultVal = param[\default];
		currentVal = if(existingData.notNil, { existingData[paramName] ? defaultVal }, { defaultVal });
		showIf = param[\showIf];
		shouldShow = true;

		if(showIf.notNil, {
			showIf.keysValuesDo { |depName, depExpected|
				var depSym = depName.asSymbol;
				var depValue = currentParamValues[depSym];
				if(depValue.isNil && existingData.notNil, {
					depValue = existingData[depSym];
				});
				if(depValue.isNil, {
					var depParam = parameters.detect { |p| p[\name].asSymbol == depSym };
					if(depParam.notNil, { depValue = depParam[\default]; });
				});
				if(depValue.asSymbol != depExpected.asSymbol, {
					shouldShow = false;
				});
			};
		});

		if(shouldShow, {
			row = View(container).layout_(HLayout().margins_(0).spacing_(5));
			StaticText(row, 150@25).string_(label ++ ":").align_(\right);

		case
		{ paramType == \int } {
			var min, max;
			min = param[\min] ? 1;
			max = param[\max] ? 100;
			paramWidgets[paramName] = NumberBox(row, 120@25)
				.value_(currentVal.asInteger)
				.decimals_(0)
				.clipLo_(min)
				.clipHi_(max);
		}
		{ paramType == \float } {
			paramWidgets[paramName] = NumberBox(row, 120@25)
				.value_(currentVal)
				.clipLo_(param[\min] ? -1e38)
				.clipHi_(param[\max] ? 1e38);
		}
		{ paramType == \choice } {
			var options, selectedIdx;
			options = param[\options] ? [];
			selectedIdx = options.collect(_.asSymbol).indexOf(currentVal.asSymbol) ? 0;
			paramWidgets[paramName] = PopUpMenu(row, 250@25)
				.items_(options)
				.value_(selectedIdx)
				.action_({ |menu|
					if(paramName == \runtimeMode && rebuildFunc.notNil, {
						rebuildFunc.value;
					});
				});
			currentParamValues[paramName] = if(options.size > 0, { options[selectedIdx].asSymbol }, { currentVal.asSymbol });
		}
		{ paramType == \bool } {
			paramWidgets[paramName] = CheckBox(row, 25@25).value_(currentVal.asBoolean);
			currentParamValues[paramName] = currentVal.asBoolean;
		}
		{ paramType == \text } {
			paramWidgets[paramName] = TextField(row, 250@25)
				.string_(if(currentVal.notNil, { currentVal.asString }, { "" }));
			currentParamValues[paramName] = if(currentVal.notNil, { currentVal.asString }, { "" });
		}
		{ paramType == \file } {
			var fileField;
			fileField = TextField(row, 180@25)
				.string_(if(currentVal.notNil, { currentVal.asString }, { "" }));
			paramWidgets[paramName] = fileField;
			Button(row, 70@25)
				.states_([["Browse"]])
				.action_({
					FileDialog({ |paths|
						if(paths.notNil && (paths.size > 0), {
							fileField.string = paths[0].asString;
						});
					});
				});
			Button(row, 50@25)
				.states_([["Clear"]])
				.action_({ fileField.string = ""; });
			currentParamValues[paramName] = if(currentVal.notNil, { currentVal.asString }, { "" });
		}
		{ paramType == \multilineText } {
			row.remove;
			StaticText(container, 150@20).string_(label ++ ":").align_(\right);
			paramWidgets[paramName] = TextView(container, 410@90)
				.string_(if(currentVal.notNil, { currentVal.asString }, { "" }));
			currentParamValues[paramName] = if(currentVal.notNil, { currentVal.asString }, { "" });
		}
		{ paramType == \array } {
			// Store the raw value for pass-through; display as read-only info
			paramWidgets[paramName] = currentVal;
			StaticText(row, 250@25)
				.string_("(% items - edit in preset file)".format(currentVal.size))
				.background_(Color.gray(0.85));
			currentParamValues[paramName] = currentVal;
		}
			{ /* default */
				paramWidgets[paramName] = NumberBox(row, 100@25).value_(currentVal ? 0);
				currentParamValues[paramName] = currentVal ? 0;
			};
		}, {
			currentParamValues[paramName] = currentVal;
		});
	};
};

// =============================================================================
// PARAMETER COLLECTION FUNCTIONS
// =============================================================================

~collectInputParameters = { |inputType|
	var config, metadata, parameters;

	config = (
		id: paramWidgets[\id].string.asSymbol,
		type: inputType,
		startBar: paramWidgets[\startBar].value.asInteger,
		startBeat: paramWidgets[\startBeat].value.asInteger,
		durationBeats: paramWidgets[\durationBeats].value.asInteger,
		outBus: paramWidgets[\outBus].value.asInteger
	);

	metadata = ~inputTypes[inputType];
	if(metadata.notNil, {
		parameters = metadata[\parameters] ? [];
		parameters.do { |param|
			var paramName, paramType, widget, value;
			paramName = param[\name].asSymbol;
			paramType = param[\type].asSymbol;
			widget = paramWidgets[paramName];

			if(widget.notNil, {
				case
				{ paramType == \int } {
					value = widget.value.round(1).asInteger;
				}
				{ paramType == \float } {
					value = widget.value;
				}
				{ paramType == \choice } {
					var options = param[\options] ? [];
					value = if(options.size > 0, { options[widget.value].asSymbol }, { nil });
				}
				{ paramType == \bool } {
					value = widget.value.asBoolean;
				}
				{ (paramType == \text) || (paramType == \file) || (paramType == \multilineText) } {
					value = widget.string;
				}
				{ paramType == \array } {
					// widget holds the raw array directly (not a GUI object)
					value = widget;
				}
				{ value = widget.value; };

				config[paramName] = value;
			});
		};
	});

	config;
};

~collectOutputParameters = { |outputType|
	var config, metadata, parameters, sourceItem;

	// Only collect source if the widget exists (output type requires source)
	// Use sourceIDs array (actual buffer IDs) instead of display labels
	sourceItem = if(paramWidgets[\source].notNil, {
		var sourceIDs = paramWidgets[\sourceIDs];
		var idx = paramWidgets[\source].value;
		if(sourceIDs.notNil && (idx < sourceIDs.size), { sourceIDs[idx].asSymbol }, { nil });
	}, { nil });

	config = (
		id: paramWidgets[\id].string.asSymbol,
		type: outputType,
		bar: paramWidgets[\bar].value.asInteger,
		beat: paramWidgets[\beat].value.asInteger,
		outBus: paramWidgets[\outBus].value.asInteger
	);
	
	// Only add source to config if it was collected (output requires input)
	if(sourceItem.notNil, {
		config[\source] = sourceItem;
	});

	metadata = ~outputTypes[outputType];
	if(metadata.notNil, {
		parameters = metadata[\parameters] ? [];
		parameters.do { |param|
			var paramName, paramType, widget, value;
			paramName = param[\name].asSymbol;
			paramType = param[\type].asSymbol;
			widget = paramWidgets[paramName];

			if(widget.notNil, {
				case
				{ paramType == \int } {
					value = widget.value.round(1).asInteger;
				}
				{ paramType == \float } {
					value = widget.value;
				}
				{ paramType == \choice } {
					var options = param[\options] ? [];
					value = if(options.size > 0, { options[widget.value].asSymbol }, { nil });
				}
				{ paramType == \bool } {
					value = widget.value.asBoolean;
				}
				{ (paramType == \text) || (paramType == \file) || (paramType == \multilineText) } {
					value = widget.string;
				}
				{ paramType == \array } {
					// widget holds the raw array directly (not a GUI object)
					value = widget;
				}
				{ value = widget.value; };

				config[paramName] = value;
			});
		};
	});

	config;
};

// =============================================================================
// PARAMETER EDITOR BUILDERS
// =============================================================================

~buildInputParameterEditor = { |inputType, existingData|
	{
		var metadata, availableTypes, container, row;
		paramWidgets = IdentityDictionary.new;
		paramEditorView.removeAll;

		container = View();
		paramEditorView.layout = VLayout(
			ScrollView().canvas_(container).minHeight_(400)
		).margins_(0);

		container.layout = VLayout().margins_(10).spacing_(5);

		// Header
		StaticText(container)
			.string_(if(isEditMode, "Edit Input", "Add Input"))
			.font_(Font.default.size_(16).bold_(true))
			.align_(\center)
			.background_(Color.gray(0.85))
			.minHeight_(30);

		// Type selector
		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Type:").align_(\right);
		if(isEditMode, {
			metadata = ~inputTypes[inputType];
			StaticText(row, 250@25)
				.string_(if(metadata.notNil, { metadata[\displayName] ? inputType }, { inputType }))
				.background_(Color.gray(0.9));
		}, {
			availableTypes = ~inputTypes.keys.asArray.sort;
			if(availableTypes.size > 0, {
				paramWidgets[\typeMenu] = PopUpMenu(row, 250@25)
					.items_(availableTypes.collect({ |k|
						var m = ~inputTypes[k];
						if(m.notNil, { m[\displayName] ? k.asString }, { k.asString });
					}))
					.value_(availableTypes.indexOf(inputType) ? 0)
					.action_({ |menu|
						if(menu.value < availableTypes.size, {
							~buildInputParameterEditor.value(availableTypes[menu.value], nil);
						});
					});
			}, {
				StaticText(row, 250@25).string_("(no input types found)").background_(Color.gray(0.9));
			});
		});

		// ID
		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("ID:").align_(\right);
		paramWidgets[\id] = TextField(row, 310@25)
			.string_(if(existingData.notNil, { existingData[\id].asString }, { "" }));

		// Routing
		StaticText(container).string_("Routing").font_(Font.default.bold_(true)).minHeight_(25);

		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Output Bus:").align_(\right);
		paramWidgets[\outBus] = NumberBox(row, 60@25)
			.value_(if(existingData.notNil, { existingData[\outBus] ? 0 }, { 0 }))
			.decimals_(0)
			.clipLo_(0);
		StaticText(row).string_("(0 = default stereo out)").font_(Font.default.size_(10));

		// Timing
		StaticText(container).string_("Timing").font_(Font.default.bold_(true)).minHeight_(25);

		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Start Position:").align_(\right);
		StaticText(row, 30@25).string_("Bar:");
		paramWidgets[\startBar] = NumberBox(row, 50@25)
			.value_(if(existingData.notNil, { existingData[\startBar] ? 2 }, { 2 }))
			.decimals_(0);
		StaticText(row, 35@25).string_("Beat:");
		paramWidgets[\startBeat] = NumberBox(row, 50@25)
			.value_(if(existingData.notNil, { existingData[\startBeat] ? 1 }, { 1 }))
			.decimals_(0);

		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Duration (beats):").align_(\right);
		paramWidgets[\durationBeats] = NumberBox(row, 100@25)
			.value_(if(existingData.notNil, { existingData[\durationBeats] ? 4 }, { 4 }))
			.decimals_(0);

		// Type-specific parameters
		metadata = ~inputTypes[inputType];
		if(metadata.notNil, {
			if(metadata[\parameters].notNil, {
				if(metadata[\parameters].size > 0, {
					StaticText(container).string_("Parameters").font_(Font.default.bold_(true)).minHeight_(25);
					~generateParameterWidgets.value(container, metadata, existingData, {
						var currentConfig;
						currentConfig = ~collectInputParameters.value(inputType);
						~buildInputParameterEditor.value(inputType, currentConfig);
					});
				});
			});
		});

		// Buttons
		row = View(container).layout_(HLayout().margins_(0).spacing_(10));
		View(row); // spacer
		Button(row).minWidth_(100).fixedHeight_(30)
			.states_([["Cancel"]])
			.action_({
				~clearParameterEditor.value;
				selectedInstance = nil;
				isEditMode = false;
			});
		Button(row).minWidth_(100).fixedHeight_(30)
			.states_([["Save", Color.white, Color.green(0.6)]])
			.action_({
				var config, success;
				config = ~collectInputParameters.value(inputType);
				if(isEditMode, {
					success = ~updateInput.value(selectedInstance[\id], config);
				}, {
					success = ~addInput.value(config);
				});
				if(success, {
					~clearParameterEditor.value;
					selectedInstance = nil;
					isEditMode = false;
				});
			});

	}.defer;
};

~buildOutputParameterEditor = { |outputType, existingData|
	{
		var metadata, availableTypes, availableSources, container, row;
		paramWidgets = IdentityDictionary.new;
		paramEditorView.removeAll;

		container = View();
		paramEditorView.layout = VLayout(
			ScrollView().canvas_(container).minHeight_(400)
		).margins_(0);

		container.layout = VLayout().margins_(10).spacing_(5);

		// Header
		StaticText(container)
			.string_(if(isEditMode, "Edit Output", "Add Output"))
			.font_(Font.default.size_(16).bold_(true))
			.align_(\center)
			.background_(Color.gray(0.85))
			.minHeight_(30);

		// Type selector
		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Type:").align_(\right);
		if(isEditMode, {
			metadata = ~outputTypes[outputType];
			StaticText(row, 250@25)
				.string_(if(metadata.notNil, { metadata[\displayName] ? outputType }, { outputType }))
				.background_(Color.gray(0.9));
		}, {
			availableTypes = ~outputTypes.keys.asArray.sort;
			if(availableTypes.size > 0, {
				paramWidgets[\typeMenu] = PopUpMenu(row, 250@25)
					.items_(availableTypes.collect({ |k|
						var m = ~outputTypes[k];
						if(m.notNil, { m[\displayName] ? k.asString }, { k.asString });
					}))
					.value_(availableTypes.indexOf(outputType) ? 0)
					.action_({ |menu|
						if(menu.value < availableTypes.size, {
							~buildOutputParameterEditor.value(availableTypes[menu.value], nil);
						});
					});
			}, {
				StaticText(row, 250@25).string_("(no output types found)").background_(Color.gray(0.9));
			});
		});

		// ID
		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("ID:").align_(\right);
		paramWidgets[\id] = TextField(row, 310@25)
			.string_(if(existingData.notNil, { existingData[\id].asString }, { "" }));

		// Routing
		StaticText(container).string_("Routing").font_(Font.default.bold_(true)).minHeight_(25);

		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Output Bus:").align_(\right);
		paramWidgets[\outBus] = NumberBox(row, 60@25)
			.value_(if(existingData.notNil, { existingData[\outBus] ? 0 }, { 0 }))
			.decimals_(0)
			.clipLo_(0);
		StaticText(row).string_("(0 = default stereo out; set by FX chain when chained)").font_(Font.default.size_(10));

		// Buffer Source - only show if the output type requires an input source
		// Note: Outputs read from buffers, not directly from input synths.
		// Input synths write to bufferDict[inputID], so we list buffer IDs here.
		metadata = ~outputTypes[outputType];
		if(metadata.notNil, {
			if(metadata[\requiredInputType].notNil, {
				var sourceIDs, sourceLabels, selectedIdx;
			sourceIDs = [];
			sourceLabels = [];

			// Add buffers created by inputs (buffer ID = input ID)
			inputs.do({ |inp|
				var label = "% (from %)".format(inp[\id], inp[\type]);
				sourceIDs = sourceIDs.add(inp[\id]);
				sourceLabels = sourceLabels.add(label);
			});

			// Add preloaded buffers
			preloadBuffers.do({ |buf|
				var label = "% (preloaded)".format(buf[\id]);
				sourceIDs = sourceIDs.add(buf[\id]);
				sourceLabels = sourceLabels.add(label);
			});

			if(sourceIDs.size == 0, {
				sourceIDs = [\none];
				sourceLabels = ["(no buffers available)"];
			});

			// Store sourceIDs for later retrieval in ~collectOutputParameters
			paramWidgets[\sourceIDs] = sourceIDs;

			// Find selected index for existing data
			selectedIdx = if(existingData.notNil, {
				if(existingData[\source].notNil, {
					sourceIDs.indexOf(existingData[\source]) ? 0;
				}, { 0 });
			}, { 0 });

			row = View(container).layout_(HLayout().margins_(0).spacing_(5));
			StaticText(row, 150@25).string_("Buffer Source:").align_(\right);
			paramWidgets[\source] = PopUpMenu(row, 250@25)
				.items_(sourceLabels)
				.value_(selectedIdx);
			});
		});

		// Timing
		StaticText(container).string_("Timing").font_(Font.default.bold_(true)).minHeight_(25);

		row = View(container).layout_(HLayout().margins_(0).spacing_(5));
		StaticText(row, 150@25).string_("Trigger Position:").align_(\right);
		StaticText(row, 30@25).string_("Bar:");
		paramWidgets[\bar] = NumberBox(row, 50@25)
			.value_(if(existingData.notNil, { existingData[\bar] ? 5 }, { 5 }))
			.decimals_(0);
		StaticText(row, 35@25).string_("Beat:");
		paramWidgets[\beat] = NumberBox(row, 50@25)
			.value_(if(existingData.notNil, { existingData[\beat] ? 1 }, { 1 }))
			.decimals_(0);

		// Type-specific parameters
		metadata = ~outputTypes[outputType];
		if(metadata.notNil, {
			if(metadata[\parameters].notNil, {
				if(metadata[\parameters].size > 0, {
					StaticText(container).string_("Parameters").font_(Font.default.bold_(true)).minHeight_(25);
					~generateParameterWidgets.value(container, metadata, existingData, {
						var currentConfig;
						currentConfig = ~collectOutputParameters.value(outputType);
						~buildOutputParameterEditor.value(outputType, currentConfig);
					});
				});
			});
		});

		// Buttons
		row = View(container).layout_(HLayout().margins_(0).spacing_(10));
		View(row); // spacer
		Button(row).minWidth_(100).fixedHeight_(30)
			.states_([["Cancel"]])
			.action_({
				~clearParameterEditor.value;
				selectedInstance = nil;
				isEditMode = false;
			});
		Button(row).minWidth_(100).fixedHeight_(30)
			.states_([["Save", Color.white, Color.green(0.6)]])
			.action_({
				var config, success;
				config = ~collectOutputParameters.value(outputType);
				if(isEditMode, {
					success = ~updateOutput.value(selectedInstance[\id], config);
				}, {
					success = ~addOutput.value(config);
				});
				if(success, {
					~clearParameterEditor.value;
					selectedInstance = nil;
					isEditMode = false;
				});
			});

	}.defer;
};

// =============================================================================
// HELP FUNCTION
// =============================================================================

~showHelp = {
	{
		var helpWindow, helpText, inputTypeList, outputTypeList;

		inputTypeList = if(~inputTypes.size > 0, {
			~inputTypes.keys.asArray.sort.collect({ |key|
				var meta = ~inputTypes[key];
				"- % (%)".format(key, if(meta.notNil, { meta[\displayName] ? key }, { key }));
			}).join("\n");
		}, { "(none)" });

		outputTypeList = if(~outputTypes.size > 0, {
			~outputTypes.keys.asArray.sort.collect({ |key|
				var meta = ~outputTypes[key];
				"- % (%)".format(key, if(meta.notNil, { meta[\displayName] ? key }, { key }));
			}).join("\n");
		}, { "(none)" });

		helpText = "
Routines Configuration GUI

WORKFLOW:
1. Add inputs and outputs using the buttons
2. Save preset to .preset file
3. Edit presetPath in routines.scd if needed, then click Reload routines
   (or run routines.scd manually in the IDE)
4. Run metronome.scd to trigger routines

AVAILABLE INPUT TYPES:
%

AVAILABLE OUTPUT TYPES:
%

PRESET FORMAT:
- audioInputBus: hardware input (default 0)
- synthdefs: SynthDef files to load
- preloadBuffers: audio files to preload
- inputs: input routine configurations
- outputs: output routine configurations

INPUT FIELDS:
- id: unique identifier
- type: routine type (matches filename)
- startBar, startBeat: when to start
- durationBeats: how long to run

OUTPUT FIELDS:
- id: unique identifier
- type: routine type (matches filename)
- source: input ID to read from
- bar, beat: when to trigger

TIPS:
- Use Duplicate to quickly create similar items
- Outputs must have valid source inputs
- Save regularly to avoid losing work
		".format(inputTypeList, outputTypeList);

		helpWindow = Window("Help", Rect(200, 200, 500, 500)).front;
		helpWindow.layout = VLayout(
			TextView().string_(helpText).editable_(false),
			Button().states_([["Close"]]).action_({ helpWindow.close; })
		).margins_(10);
	}.defer;
};

// =============================================================================
// CREATE MAIN WINDOW
// =============================================================================

{
	mainWindow = Window("Routines Configuration GUI", Rect(100, 100, 850, 600))
		.front
		.onClose_({
			if(hasUnsavedChanges, {
				"Warning: Closing with unsaved changes".postln;
			});
		});

	mainWindow.layout = VLayout(
		// Top toolbar
		HLayout(
			Button().minWidth_(80).states_([["New", Color.black, Color.cyan(0.7)]])
				.action_({ ~newPreset.value; }),
			Button().minWidth_(80).states_([["Load...", Color.black, Color.gray(0.8)]])
				.action_({ ~loadPresetDialog.value; }),
			Button().minWidth_(80).states_([["Save...", Color.black, Color.green(0.7)]])
				.action_({ ~savePresetDialog.value; }),
			Button().minWidth_(80).states_([["Rescan", Color.black, Color.yellow(0.7)]])
				.action_({ ~scanRoutineFolders.value; ~scanSynthdefs.value; }),
			Button().minWidth_(120).states_([["Reload routines", Color.black, Color.magenta(0.55)]])
				.action_({ ~reloadRoutines.value; }),
			Button().minWidth_(60).states_([["Help", Color.black, Color.yellow(0.7)]])
				.action_({ ~showHelp.value; }),
			nil
		).margins_(5),

		// Main content
		HLayout(
			// Left panel - lists
			VLayout(
			HLayout(
				processTabButton = Button().minWidth_(90)
					.states_([
						["Process", Color.black, Color.white],
						["Process", Color.black, Color.green(0.8)]
					])
					.value_(1)
					.action_({
						{
							currentTab = \process;
							processTabButton.value = 1;
							bufferTabButton.value = 0;
							routingTabButton.value = 0;
							listStack.index = 0;
							~clearParameterEditor.value;
						}.defer;
					}),
				bufferTabButton = Button().minWidth_(70)
					.states_([
						["Buffers", Color.black, Color.white],
						["Buffers", Color.black, Color.green(0.8)]
					])
					.value_(0)
					.action_({
						{
							currentTab = \buffers;
							processTabButton.value = 0;
							bufferTabButton.value = 1;
							routingTabButton.value = 0;
							listStack.index = 1;
							~clearParameterEditor.value;
						}.defer;
					}),
				routingTabButton = Button().minWidth_(70)
					.states_([
						["Routing", Color.black, Color.white],
						["Routing", Color.black, Color.green(0.8)]
					])
					.value_(0)
					.action_({
						{
							currentTab = \routing;
							processTabButton.value = 0;
							bufferTabButton.value = 0;
							routingTabButton.value = 1;
							listStack.index = 2;
							~clearParameterEditor.value;
						}.defer;
					})
			),

			View().minWidth_(310).minHeight_(350).layout_(
				listStack = StackLayout(
					processListView  = ListView().items_([]),
					bufferListView   = ListView().items_([]),
					routingListView  = ListView().items_([])
				).index_(0)
			),

				// Action buttons
				HLayout(
					Button().minWidth_(60).states_([["Add", Color.black, Color.green(0.7)]])
						.action_({
							selectedInstance = nil;
							isEditMode = false;
							if(currentTab == \process, {
								// Show a popup to choose input or output type
								var allInputTypes  = ~inputTypes.keys.asArray.sort;
								var allOutputTypes = ~outputTypes.keys.asArray.sort;
								var menuItems = [];
								var menuKinds = [];   // parallel array: \input or \output

								// Build grouped menu: "--- Inputs ---" header, then each type
								menuItems = menuItems.add("--- Inputs ---");
								menuKinds  = menuKinds.add(nil);
								allInputTypes.do { |k|
									var m = ~inputTypes[k];
									menuItems = menuItems.add(
										"[IN]  " ++ (if(m.notNil, { m[\displayName] ? k.asString }, { k.asString }))
									);
									menuKinds = menuKinds.add((\role: \input, \type: k));
								};
								menuItems = menuItems.add("--- Outputs ---");
								menuKinds  = menuKinds.add(nil);
								allOutputTypes.do { |k|
									var m = ~outputTypes[k];
									menuItems = menuItems.add(
										"[OUT] " ++ (if(m.notNil, { m[\displayName] ? k.asString }, { k.asString }))
									);
									menuKinds = menuKinds.add((\role: \output, \type: k));
								};

								if((allInputTypes.size + allOutputTypes.size) == 0, {
									~showError.value("No Types", "No routines found in inputs/ or outputs/ folders.");
								}, {
									{
										var popup = Window("Add Process", Rect(300, 300, 350, 180)).front;
										var menu, menuView;
										popup.layout = VLayout(
											StaticText().string_("Select type to add:").align_(\center),
											menuView = PopUpMenu().items_(menuItems),
											HLayout(
												nil,
												Button().states_([["Cancel"]]).minWidth_(80)
													.action_({ popup.close; }),
												Button().states_([["Add", Color.white, Color.green(0.6)]]).minWidth_(80)
													.action_({
														var sel = menuView.value;
														var kind = menuKinds[sel];
														popup.close;
														if(kind.notNil, {
															if(kind[\role] == \input, {
																~buildInputParameterEditor.value(kind[\type], nil);
															}, {
																~buildOutputParameterEditor.value(kind[\type], nil);
															});
														});
													})
											)
										).margins_(15);
									}.defer;
								});
							});
							if(currentTab == \buffers, {
								~showAddBufferDialog.value;
							});
							if(currentTab == \routing, {
								~buildRoutingEditor.value;
							});
						}),
					Button().minWidth_(60).states_([["Edit", Color.black, Color.yellow(0.7)]])
						.action_({
							if(currentTab == \process, {
								var sel = processListView.value;
								if(sel.notNil && sel >= 0 && sel < processItems.size, {
									var item = processItems[sel];
									if(item[\role] == \input, {
										selectedInstance = inputs[item[\idx]];
										isEditMode = true;
										~buildInputParameterEditor.value(selectedInstance[\type], selectedInstance);
									}, {
										selectedInstance = outputs[item[\idx]];
										isEditMode = true;
										~buildOutputParameterEditor.value(selectedInstance[\type], selectedInstance);
									});
								});
							});
							if(currentTab == \buffers, {
								if(bufferListView.value >= 0 && bufferListView.value < preloadBuffers.size, {
									var buf = preloadBuffers[bufferListView.value];
									~showInfo.value("Buffer Info",
										"ID: %\nPath: %".format(buf[\id], buf[\path]));
								});
							});
							if(currentTab == \routing, {
								if(routingListView.value >= 0 && routingListView.value < fxChains.size, {
									~buildRoutingEditor.value(routingListView.value);
								});
							});
						}),
					Button().minWidth_(60).states_([["Dup", Color.black, Color.blue(0.7)]])
						.action_({
							if(currentTab == \process, {
								var sel = processListView.value;
								if(sel.notNil && sel >= 0 && sel < processItems.size, {
									var item = processItems[sel];
									if(item[\role] == \input, {
										~duplicateInput.value(inputs[item[\idx]][\id]);
									}, {
										~duplicateOutput.value(outputs[item[\idx]][\id]);
									});
								});
							});
						}),
					Button().minWidth_(60).states_([["Del", Color.black, Color.red(0.7)]])
						.action_({
							if(currentTab == \process, {
								var sel = processListView.value;
								if(sel.notNil && sel >= 0 && sel < processItems.size, {
									var item = processItems[sel];
									if(item[\role] == \input, {
										~removeInput.value(inputs[item[\idx]][\id]);
									}, {
										~removeOutput.value(outputs[item[\idx]][\id]);
									});
								});
							});
							if(currentTab == \buffers, {
								if(bufferListView.value >= 0 && bufferListView.value < preloadBuffers.size, {
									~removeBuffer.value(preloadBuffers[bufferListView.value][\id]);
								});
							});
							if(currentTab == \routing, {
								if(routingListView.value >= 0 && routingListView.value < fxChains.size, {
									~removeRouting.value(routingListView.value);
								});
							});
						})
				)
			).margins_(5),

			// Right panel - parameter editor
			VLayout(
				paramEditorView = View().background_(Color.gray(0.95)).minWidth_(500)
			).margins_(5)
		).margins_(5),

		// Status bar
		HLayout(
			statusBarText = StaticText()
				.string_("Preset: <unsaved> | Process: 0 | Buffers: 0 | Saved")
				.font_(Font.monospace.size_(11))
		).margins_(5)
	).margins_(10);

	~clearParameterEditor.value;
	~refreshProcessList.value;
	~updateStatusBar.value;

	"".postln;
	"=== Routines Configuration GUI Ready ===".postln;
	"".postln;
}.defer;
)
