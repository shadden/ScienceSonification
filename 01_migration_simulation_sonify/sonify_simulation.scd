/* Evaluate this whole file, then select the notebook's sonification.json.
   The WAV is rendered offline (no boot, bus resets, or live recording needed).
   The script and rv_buffer_fill.scd must be in the same directory.
   Optional: set ~sonificationConfigPath to an absolute JSON path first.
*/
(
var scriptPath = thisProcess.nowExecutingPath;
var helperPath, render;
if(scriptPath.isNil) {
    Error("Save this script, then evaluate the whole file from the editor.").throw;
};
helperPath = PathName(scriptPath).pathOnly +/+ "rv_buffer_fill.scd";
helperPath.load;

render = { |configPath|
    var cfg, resolve, readCsv, nData, eData, nPl, nSamples;
    var dur, sampleRate, nMul, eMul, atk, rel, totalAmp, nWT, nEcc;
    var outputPath, rawPath, oscPath, tables, score, options, def;
    var addBuffer, nextBuf = 0, tableBase, nIds, eIds, tempo;
    cfg = configPath.parseJSONFile;
    if(cfg["schema_version"].asInteger != 1) {
        Error("Unsupported sonification schema_version").throw;
    };
    resolve = { |key|
        var path = cfg[key];
        if(path.isNil) { Error("Missing JSON key: " ++ key).throw };
        if(PathName(path).isAbsolutePath) { path } {
            PathName(configPath).pathOnly +/+ path
        };
    };
    readCsv = { |key|
        var path = resolve.(key), rows;
        if(File.exists(path).not) { Error("Missing file: " ++ path).throw };
        rows = CSVFileReader.read(path, skipEmptyLines: true, skipBlanks: true);
        rows.collect { |row| row.collect { |value| value.asFloat } };
    };
    nData = readCsv.("frequency_csv");
    eData = readCsv.("eccentricity_csv");
    nPl = cfg["n_planets"].asInteger;
    nSamples = cfg["n_samples"].asInteger;
    dur = cfg["duration_seconds"].asFloat;
    sampleRate = cfg["audio_sample_rate"].asInteger;
    nMul = cfg["frequency_multiplier"].asFloat;
    eMul = cfg["eccentricity_multiplier"].asFloat;
    atk = cfg["fade_in_seconds"].asFloat;
    rel = cfg["fade_out_seconds"].asFloat;
    totalAmp = cfg["total_amplitude"].asFloat;
    nWT = cfg["wavetable_samples"].asInteger;
    nEcc = cfg["wavetable_count"].asInteger;
    if((nPl < 1) or: { nSamples < 2 } or: { dur <= 0 }
        or: { sampleRate <= 0 } or: { nMul <= 0 } or: { eMul < 0 }
        or: { atk < 0 } or: { rel < 0 } or: { (atk + rel) > dur }
        or: { totalAmp < 0 } or: { nEcc < 2 }
        or: { nWT < 2 } or: { nWT.isPowerOfTwo.not }) {
        Error("Invalid duration, planet count, fade, gain, or wavetable settings").throw;
    };
    [nData, eData].do { |rows|
        if((rows.size != nSamples) or: {
            rows.any { |row| row.size != nPl }
        }) { Error("CSV dimensions disagree with JSON n_samples/n_planets").throw };
    };
    if(nData.any { |row| row.any { |v| v <= 0 } }) {
        Error("Orbital frequencies must be positive").throw;
    };
    outputPath = resolve.("recording_file");
    rawPath = outputPath ++ ".render.wav";
    oscPath = outputPath ++ ".osc";
    // Score uses beats. Scale event times to preserve seconds at any tempo.
    tempo = TempoClock.default.tempo;
    score = Score([]);
    addBuffer = {
		|data|
        var id = nextBuf;
        nextBuf = nextBuf + 1;
        score.add([0.0, [\b_alloc, id, data.size, 1]]);
        // Chunk large CSV columns to stay below the OSC message size limit.
        data.clump(1000).do { |chunk, i|
            score.add([0.0, [\b_setn, id, i * 1000, chunk.size] ++ chunk]);
        };
        id;
    };
    tables = ~makeRVTables.(nWT, nEcc)[0]; // cosine RV family, as before
    tableBase = nextBuf;
    tables.do { |table| addBuffer.(table.asArray) };
    nIds = nData.flop.collect { |data| addBuffer.(data) };
    eIds = eData.flop.collect { |data| addBuffer.(data) };

    def = SynthDef(\migrationOrbitNRT, {
        |nBuf = 0, eBuf = 1, rvBase = 0, rvCount = 20,
         duration = 15, nScale = 20, eScale = 30,
         attack = 0.1, release = 1, amp = 0.1|
        var phase, freq, ecc, bpos, env, snd;
        phase = Line.ar(0, 1, duration);
        freq = BufRd.ar(1, nBuf, phase * (BufFrames.ir(nBuf) - 1),
            loop: 0, interpolation: 2) * nScale;
        ecc = (BufRd.ar(1, eBuf, phase * (BufFrames.ir(eBuf) - 1),
            loop: 0, interpolation: 2) * eScale).clip(0, 0.98);
        // Buffer positions are absolute: do not assume the bank starts at 0.
        // Keep the upper endpoint just below the last table (VOsc interpolates).
        bpos = rvBase + ((ecc / 0.98) * (rvCount - 1)).min(rvCount - 1.00001);
        env = EnvGen.ar(Env.linen(attack,
            (duration - attack - release).max(0), release),
            doneAction: Done.freeSelf);
        snd = VOsc.ar(bpos, freq) * env * amp;
        Out.ar(0, snd ! 2);
    });
    score.add([0.0, [\d_recv, def.asBytes]]);
    nPl.do { |i|
        score.add([0.0, [\s_new, \migrationOrbitNRT, 1000 + i, 0, 1,
            \nBuf, nIds[i], \eBuf, eIds[i],
            \rvBase, tableBase, \rvCount, nEcc, \duration, dur,
            \nScale, nMul, \eScale, eMul, \attack, atk, \release, rel,
            \amp, totalAmp / nPl]]);
    };
    score.add([dur * tempo, [0]]);
    // Keep the insertion order at t=0: allocate -> fill -> define -> synth.
    options = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0);
    options.numBuffers = nextBuf + 32;
    options.maxNodes = nPl + 64;
    options.memSize = 65536;
    ("Rendering " ++ nPl ++ " planets, " ++ dur ++ " seconds...").postln;
    score.recordNRT(oscFilePath: oscPath, outputFilePath: rawPath,
        sampleRate: sampleRate, headerFormat: "WAV", sampleFormat: "float",
        options: options, duration: dur * tempo,
        action: { |exitCode|
            // NRT output can be rounded to a server block. Trim to the desired
            // sample count, without adding a release tail after the video.
            var input, output, framesLeft, count, data, targetFrames;
            if(exitCode != 0) {
                ("Rendering failed; scsynth exit code: " ++ exitCode).warn;
            } {
                input = SoundFile.new;
                if(input.openRead(rawPath).not) { Error("Cannot read rendered WAV").throw };
                targetFrames = (dur * sampleRate).round.asInteger;
                if(input.numFrames < targetFrames) {
                    input.close;
                    Error("Rendered WAV is shorter than the requested duration").throw;
                };
                output = SoundFile.new.headerFormat_("WAV").sampleFormat_("float")
                    .numChannels_(2).sampleRate_(sampleRate);
                if(output.openWrite(outputPath).not) {
                    input.close; Error("Cannot write " ++ outputPath).throw;
                };
                protect {
                    framesLeft = targetFrames;
                    while { framesLeft > 0 } {
                        count = framesLeft.min(65536);
                        data = FloatArray.newClear(count * 2);
                        input.readData(data);
                        output.writeData(data);
                        framesLeft = framesLeft - count;
                    };
                } { input.close; output.close };
                File.delete(rawPath);
                File.delete(oscPath);
                ("Finished: " ++ outputPath).postln;
            };
        }
    );
};
if(~sonificationConfigPath.notNil) {
    render.(~sonificationConfigPath.standardizePath);
} {
    Dialog.openPanel({ |path| render.(path) }, { "Cancelled".postln });
};
)
