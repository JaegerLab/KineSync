function tests = test_ephys
% ephys data types and the ephys .mat file. No GUI needed.
tests = functiontests(localfunctions);
end

function ephysData = sampleEphys()
t = (0:9)'/10;
ephysData.analogChannels = {'A', 'B'};
ephysData.sync = struct('method', 'All frames', 'frames', '[1:end]', 'syncVideoTime', (0:0.1:0.5)', ...
    'videoAnchor', (1:6)', 'ephysAnchor', (0:0.1:0.5)', 'digitalChannelName', 'DIN-00', 'edge', 'rising');
ephysData.displayName = 'C:\rec';
ephysData.filename = {'C:\rec\a.rhd'};
ephysData.hd = struct();
ephysData.raw = struct('data', [t 2*t], 't', t, 'sampleRate', 10);
ephysData.processed = struct('data', {t(1:2:end), 3*t(1:2:end)}, 't', {t(1:2:end), t(1:2:end)}, ...
    'sampleRate', {5, 5}, 'parameters', {struct('Source', 'Raw'), struct('Source', 'Processed 1')});
end

function testTypesSourceAndDelete(testCase)
ephysData = sampleEphys();
verifyEqual(testCase, Ephys.ephys_types(ephysData), {'Raw', 'Processed 1', 'Processed 2'});
verifyEqual(testCase, Ephys.ephys_source(ephysData, 'Processed 2').parameters.Source, 'Processed 1');
verifyEqual(testCase, Ephys.ephys_source(ephysData, 'Raw').sampleRate, 10);
verifyError(testCase, @()Ephys.ephys_source(ephysData, 'Processed 3'), 'ephys:type');
ephysData = Ephys.ephys_delete(ephysData, 'Processed 1');   % renumbered
verifyEqual(testCase, Ephys.ephys_types(ephysData), {'Raw', 'Processed 1'});
verifyEqual(testCase, Ephys.ephys_source(ephysData, 'Processed 1').parameters.Source, 'Processed 1');
ephysData = Ephys.ephys_delete(ephysData, 'Raw');
verifyEqual(testCase, Ephys.ephys_types(ephysData), {'Processed 1'});
ephysData = Ephys.ephys_delete(ephysData, 'Processed 1');
verifyEmpty(testCase, Ephys.ephys_types(ephysData));
verifyEqual(testCase, ephysData.sync.digitalChannelName, 'DIN-00');   % metadata kept
end

function testHasEphysNeedsData(testCase)
S = Shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close KineSync before running this test.');
addTeardown(testCase, @()delete(Shared.SessionData.instance()));
S.ephys = sampleEphys();
verifyTrue(testCase, S.has('ephys'));
S.ephys = Ephys.ephys_delete(S.ephys, 'Raw');
verifyTrue(testCase, S.has('ephys'));   % processed only
S.ephys.processed(:) = [];
verifyFalse(testCase, S.has('ephys'));
verifyEqual(testCase, S.getFrameRate(), 10, 'RelTol', 1e-12);   % sync still drives timing
end

function testSaveThenOpenSelectedTypes(testCase)
file = [tempname '.mat'];
addTeardown(testCase, @()delete(file));
ephysData = sampleEphys();
Ephys.save_ephys(file, ephysData, {'Raw', 'Processed 2'});
vars = who('-file', file);
verifyEqual(testCase, sort(vars), sort({'fileFormat'; 'formatVersion'; 'ephys'; 'raw'; 'processed1'}));
meta = load(file, 'ephys', 'fileFormat', 'formatVersion');
verifyFalse(testCase, any(isfield(meta.ephys, {'hd', 'raw', 'processed', 'temp'})));
verifyEqual(testCase, [string(meta.fileFormat) string(meta.formatVersion)], ["KineSync Ephys" "1"]);
[names, bytes] = Ephys.ephys_file_contents(file);
verifyEqual(testCase, names, {'raw', 'processed1'});
verifyTrue(testCase, all(bytes > 0));
% processed only: no raw in memory
loaded = Ephys.load_ephys(file, {'processed1'});
verifyEqual(testCase, Ephys.ephys_types(loaded), {'Processed 1'});
verifyEqual(testCase, loaded.processed(1).data, ephysData.processed(2).data);
verifyEqual(testCase, loaded.processed(1).parameters.Source, 'Processed 1');
verifyEqual(testCase, loaded.sync, ephysData.sync);
loaded = Ephys.load_ephys(file, names);
verifyEqual(testCase, Ephys.ephys_types(loaded), {'Raw', 'Processed 1'});
verifyEqual(testCase, loaded.raw, ephysData.raw);
% the obsolete camera trigger of older files is dropped
f = load(file, 'ephys');
f.ephys.trigger = struct('time', 0, 'freq', 10, 'number', 1);
save(file, '-struct', 'f', '-append');
verifyFalse(testCase, isfield(Ephys.load_ephys(file, names), 'trigger'));
end

function testFileContentsSortsAndRejects(testCase)
file = [tempname '.mat'];
addTeardown(testCase, @()delete(file));
fileFormat = 'KineSync Ephys'; formatVersion = 1;
p = struct('data', 1, 't', 0, 'sampleRate', 1, 'parameters', struct());
S = struct('fileFormat', fileFormat, 'formatVersion', formatVersion, 'ephys', struct(), ...
    'processed10', p, 'processed2', p);
save(file, '-struct', 'S', '-v7.3');
verifyEqual(testCase, Ephys.ephys_file_contents(file), {'processed2', 'processed10'});
formatVersion = 2;
save(file, 'formatVersion', '-append');
verifyError(testCase, @()Ephys.ephys_file_contents(file), 'ephys:file:newer');
fileFormat = 'KineSync session'; formatVersion = 1;
save(file, 'fileFormat', 'formatVersion', '-append');
verifyError(testCase, @()Ephys.ephys_file_contents(file), 'ephys:file:format');
x = 1;
save(file, 'x', '-v7.3');
verifyError(testCase, @()Ephys.ephys_file_contents(file), 'ephys:file:format');
end

function testTtlChannelsAndLabels(testCase)
t = (0:999)'/1000;   % 1 kHz, 1 s
camera = mod(0:999, 10)' < 2;   % 100 Hz, 2 ms pulses
long = t >= 0.1 & t < 0.9;      % one 0.8 s pulse
ch = Ephys.ttl_channels(t, [camera long zeros(1000,1)]);
verifyEqual(testCase, {ch.name}, {'DIN-00', 'DIN-01', 'DIN-02'});
verifyEqual(testCase, ch(1).rise, (0.01:0.01:0.99)', 'AbsTol', 1e-12);   % no edge at sample 1
verifyEqual(testCase, Ephys.ttl_stats(ch(1)), 'DIN-00: 99 TTL, 2 ms, 100 Hz');
verifyEqual(testCase, Ephys.ttl_stats(ch(2)), 'DIN-01: 1 TTL, 800 ms, - Hz');
verifyEqual(testCase, Ephys.ttl_stats(ch(3)), 'DIN-02: 0 TTL, -, - Hz');
ch = Ephys.ttl_channels(t, double(t >= 0.5), {'X'});   % no falling edge: no width
verifyEqual(testCase, Ephys.ttl_stats(ch), 'X: 1 TTL, -, - Hz');
end

function rec = fakeOpenEphys(folder, t, names, fs, ttl)
% Stand-in for an open-ephys-matlab-tools Recording with one stream 'S'
stream.timestamps = t(:);
stream.samples = int16(repmat((1:numel(names))', 1, numel(t)) + 10*round(t(:)'*fs));
stream.metadata = struct('sampleRate', fs, 'names', {names}, 'startTimestamp', t(1));
rec.directory = folder;
rec.continuous = containers.Map({'S'}, {stream});
rec.ttlEvents = containers.Map();
if nargin > 4, rec.ttlEvents('S') = ttl; end
end

function testConcatOpenEphysJoinsRecordings(testCase)
fs = 10;
ttl1 = struct('line', [1; 1], 'timestamp', [100.2; 100.4], 'state', [true; false]);
ttl2 = struct('line', [1; 2], 'timestamp', [101.1; 101.3], 'state', [true; true]);
r1 = fakeOpenEphys('x\experiment1\recording1\', 100 + (0:9)/fs, {'CH1', 'CH2'}, fs, ttl1);
r2 = fakeOpenEphys('x\experiment1\recording2\', 101 + (0:4)/fs, {'CH1', 'CH2'}, fs, ttl2);
[samples, t, digital] = Ephys.concat_openephys({r1, r2}, 'S');
verifyEqual(testCase, t, (0:14)'/fs, 'AbsTol', 1e-9);   % 0 at the first sample
verifyEqual(testCase, size(samples), [15 2]);
verifyEqual(testCase, samples(11, :), double([1 2] + 10*1010));   % second recording follows
verifyEqual(testCase, {digital.name}, {'TTL-01', 'TTL-02'});
verifyEqual(testCase, digital(1).rise, [0.2; 1.1], 'AbsTol', 1e-9);
verifyEqual(testCase, digital(1).fall, 0.4, 'AbsTol', 1e-9);
verifyEqual(testCase, digital(2).rise, 1.3, 'AbsTol', 1e-9);
end

function testConcatOpenEphysRejects(testCase)
fs = 10;
r1 = fakeOpenEphys('x\experiment1\recording1', 100 + (0:9)/fs, {'CH1', 'CH2'}, fs);
gap = fakeOpenEphys('x\experiment1\recording3', 105 + (0:4)/fs, {'CH1', 'CH2'}, fs);
[~, t] = Ephys.concat_openephys({r1, gap}, 'S');   % gap kept as real time
verifyEqual(testCase, t, [(0:9)/fs, 5 + (0:4)/fs]', 'AbsTol', 1e-9);
verifyError(testCase, @()Ephys.concat_openephys({r1, r1}, 'S'), 'ephys:openEphys:overlap');
chans = fakeOpenEphys('x\experiment1\recording2', 101 + (0:4)/fs, {'CH1'}, fs);
verifyError(testCase, @()Ephys.concat_openephys({r1, chans}, 'S'), 'ephys:openEphys:channels');
rate = fakeOpenEphys('x\experiment1\recording2', 101 + (0:4)/20, {'CH1', 'CH2'}, 20);
verifyError(testCase, @()Ephys.concat_openephys({r1, rate}, 'S'), 'ephys:openEphys:sampleRate');
other = r1; other.continuous = containers.Map({'T'}, {r1.continuous('S')});
verifyError(testCase, @()Ephys.concat_openephys({r1, other}, 'S'), 'ephys:openEphys:stream');
verifyError(testCase, @()Ephys.concat_openephys({}, 'S'), 'ephys:openEphys:empty');
% one recording works as before
[~, t] = Ephys.concat_openephys({r1}, 'S');
verifyEqual(testCase, t, (0:9)'/fs, 'AbsTol', 1e-9);
end

function testFrameRateSourcesAndOverride(testCase)
S = Shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close KineSync before running this test.');
addTeardown(testCase, @()delete(Shared.SessionData.instance()));
[rate, source] = S.getFrameRate();
verifyEqual(testCase, {rate, source}, {1, 'none'});
S.ephys = sampleEphys();   % synchronized at 0:0.1:0.5
[rate, source] = S.getFrameRate();
verifyEqual(testCase, source, 'sync');
verifyEqual(testCase, rate, 10, 'RelTol', 1e-12);
verifyEqual(testCase, S.getFrameTimes(6), S.ephys.sync.syncVideoTime);
S.setFrameRate(20);   % a typed-in rate replaces the synchronized times
[rate, source] = S.getFrameRate();
verifyEqual(testCase, {rate, source}, {20, 'manual'});
verifyEqual(testCase, S.getFrameTimes(3), (1:3)'/20);
S.setFrameRate([]);   % cleared: automatic again
verifyEqual(testCase, S.frameRate, 0);
verifyEqual(testCase, S.getFrameTimes(6), S.ephys.sync.syncVideoTime);
S.setFrameRate(0);
verifyEqual(testCase, S.frameRate, 0);
verifyError(testCase, @()S.setFrameRate(-1), 'MATLAB:expectedNonnegative');
end

function testPrepDownSamplesOnExactGrid(testCase)
t = (-0.5:0.001:2.9995)';   % starts before 0, ends between grid points
x = randn(numel(t), 1);
[y, newT] = Ephys.ephys_prep(x, t, struct('Rectify', true, 'DownSampleRate', 300), 1000);
verifyEqual(testCase, newT, (0:899)'/300, 'AbsTol', 1e-12);   % exactly 300 Hz from 0
verifyEqual(testCase, size(y), [900 1]);
verifyFalse(testCase, any(isnan(y)));
[y, newT] = Ephys.ephys_prep(x, t, struct('Rectify', true), 1000);
verifyEqual(testCase, newT, t(t>=0));
verifyEqual(testCase, y, abs(x(t>=0)));
end

function testPrepDownSamplingLeavesGapsEmpty(testCase)
fs = 1000;
t = [(0:999) (3000:3999)]'/fs;   % 0-1 s and 3-4 s, nothing in between
x = ones(numel(t), 1);
[y, newT] = Ephys.ephys_prep(x, t, struct('SmoothWindow', 1, 'DownSampleRate', 100), fs);
inGap = newT > 0.999 & newT < 3;
verifyTrue(testCase, all(isnan(y(inGap))));
verifyEqual(testCase, y(~inGap), ones(nnz(~inGap), 1), 'AbsTol', 1e-12);
verifyEqual(testCase, newT, (0:399)'/100, 'AbsTol', 1e-12);   % one regular grid
end

function testPrepSmoothWithoutDownSampling(testCase)
fs = 1000;
t = (0:999)'/fs;
x = randn(numel(t), 2);
[y, newT] = Ephys.ephys_prep(x, t, struct('SmoothWindow', 5), fs);
verifyEqual(testCase, newT, t);   % same samples
verifyEqual(testCase, y(100,:), mean(x(98:102,:)), 'AbsTol', 1e-12);   % 5-sample moving average
% with down sampling, the given window replaces the automatic one
y1 = Ephys.ephys_prep(x, t, struct('SmoothWindow', 1, 'DownSampleRate', 100), fs);
verifyEqual(testCase, y1(11,:), x(101,:), 'AbsTol', 1e-12);   % t = 0.1 s, not smoothed
y2 = Ephys.ephys_prep(x, t, struct('DownSampleRate', 100), fs);
verifyNotEqual(testCase, y2(11,:), x(101,:));
verifyError(testCase, @()Ephys.ephys_prep(x, t, struct('SmoothWindow', 2.5), fs), 'MATLAB:expectedInteger');
end

function testPrepFilterTypes(testCase)
fs = 1000;
t = (0:9999)'/fs;
lowTone = sin(2*pi*10*t); midTone = sin(2*pi*100*t); highTone = sin(2*pi*400*t);
x = lowTone + midTone + highTone;
keep = t > 1;   % skip the filter transient
power = @(y, tone) abs(mean(y(keep) .* tone(keep)));
band = struct('HighPassFreq', 50, 'LowPassFreq', 200, 'FiltFilt', true);
y = Ephys.ephys_prep(x, t, setfield(band, 'FilterType', 'bandpass'), fs);
verifyGreaterThan(testCase, power(y, midTone), 10 * power(y, lowTone));
verifyGreaterThan(testCase, power(y, midTone), 10 * power(y, highTone));
y = Ephys.ephys_prep(x, t, setfield(band, 'FilterType', 'bandstop'), fs);
verifyGreaterThan(testCase, power(y, lowTone), 10 * power(y, midTone));
verifyGreaterThan(testCase, power(y, highTone), 10 * power(y, midTone));
y = Ephys.ephys_prep(x, t, struct('FilterType', 'lowpass', 'LowPassFreq', 50), fs);
verifyGreaterThan(testCase, power(y, lowTone), 10 * power(y, highTone));
y = Ephys.ephys_prep(x, t, struct('HighPassFreq', 200), fs);   % old parameters: high pass
verifyGreaterThan(testCase, power(y, highTone), 10 * power(y, lowTone));
end

function testSaveZoomWindowKeepsTimes(testCase)
file = [tempname '.mat'];
addTeardown(testCase, @()delete(file));
ephysData = sampleEphys();
Ephys.save_ephys(file, ephysData, {'Raw', 'Processed 1'}, [0.2 0.5]);
f = load(file);
verifyEqual(testCase, f.raw.t, (2:5)'/10, 'AbsTol', 1e-12);   % absolute times, not shifted
verifyEqual(testCase, f.raw.data, ephysData.raw.data(3:6, :));
verifyEqual(testCase, f.processed1.t, [0.2; 0.4], 'AbsTol', 1e-12);
verifyEqual(testCase, f.ephys.timeRange, [0.2 0.5]);
verifyEqual(testCase, f.ephys.sync, ephysData.sync);   % metadata unchanged
Ephys.save_ephys(file, ephysData, {'Raw'});
f = load(file);
verifyEqual(testCase, f.raw, ephysData.raw);
verifyEmpty(testCase, f.ephys.timeRange);
end