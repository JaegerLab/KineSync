function [samples, t, digital] = concat_openephys(recs, keyName)
% Join consecutive Open Ephys recordings of one continuous stream.
% Syntax
%  [samples, t, digital] = Ephys.concat_openephys(recs, keyName)
%
% Parameters:
%  recs: cell array of Recording objects (open-ephys-matlab-tools), in time
%       order. Each must contain the stream keyName with the same sample rate
%       and channel names, and must start after the previous one ends. Gaps
%       between recordings are kept: t jumps over them.
%  keyName: continuous stream key, e.g. 'Rhythm_Data-100.0'
% Outputs:
%  samples: samples x channels, raw values as double, all channels
%  t: time (s), 0 at the first sample of the first recording
%  digital: TTL lines of the stream as edge times (s), see Ephys.ttl_channels

nRec = numel(recs);
if nRec == 0, error('ephys:openEphys:empty', 'No recordings selected.'); end

lens = zeros(nRec, 1);
for k = 1:nRec
    if ~isKey(recs{k}.continuous, keyName)
        error('ephys:openEphys:stream', 'Recording %s has no stream %s.', ...
            recordingName(recs{k}), keyName);
    end
    stream = recs{k}.continuous(keyName);
    lens(k) = numel(stream.timestamps);
    if k == 1
        first = stream;
        prevEnd = stream.timestamps(end);
        continue
    end
    if stream.metadata.sampleRate ~= first.metadata.sampleRate
        error('ephys:openEphys:sampleRate', ...
            'Sample rate changes from %g Hz to %g Hz at recording %s.', ...
            first.metadata.sampleRate, stream.metadata.sampleRate, recordingName(recs{k}));
    end
    if ~isequal(cellstr(stream.metadata.names), cellstr(first.metadata.names))
        error('ephys:openEphys:channels', ...
            'Channels change at recording %s (%d channels, first recording %d).', ...
            recordingName(recs{k}), numel(stream.metadata.names), numel(first.metadata.names));
    end
    % gaps are kept as real time; an overlap has no single time axis
    gap = double(stream.timestamps(1)) - double(prevEnd);
    if gap < 0.9/first.metadata.sampleRate
        error('ephys:openEphys:overlap', ...
            ['Recording %s starts before the previous one ends. ' ...
            'Recordings from different experiments restart the clock and cannot be joined.'], ...
            recordingName(recs{k}));
    end
    prevEnd = stream.timestamps(end);
end

% pre-allocate, then copy one recording at a time
nCh = numel(first.metadata.names);
samples = zeros(sum(lens), nCh);
t = zeros(sum(lens), 1);
start = double(first.timestamps(1));
p = 0;
for k = 1:nRec
    stream = recs{k}.continuous(keyName);
    samples(p+(1:lens(k)), :) = double(stream.samples(1:nCh, :)');
    t(p+(1:lens(k))) = double(stream.timestamps(:)) - start;
    p = p + lens(k);
end

% TTL lines of this stream, from every recording
lines = []; ts = []; state = [];
for k = 1:nRec
    if isKey(recs{k}.ttlEvents, keyName)
        ttl = recs{k}.ttlEvents(keyName);
        lines = [lines; double(ttl.line(:))]; %#ok<AGROW>
        ts = [ts; double(ttl.timestamp(:)) - start]; %#ok<AGROW>
        state = [state; logical(ttl.state(:))]; %#ok<AGROW>
    end
end
digital = struct('name', {}, 'rise', {}, 'fall', {});
ids = unique(lines);
for k = 1:numel(ids)
    onLine = lines == ids(k);
    digital(k).name = sprintf('TTL-%02d', ids(k));
    digital(k).rise = sort(ts(onLine & state));
    digital(k).fall = sort(ts(onLine & ~state));
end
end

function name = recordingName(rec)
% experimentN/recordingM, from the recording folder
[parent, name] = fileparts(regexprep(char(rec.directory), '[/\\]+$', ''));
[~, experiment] = fileparts(parent);
name = [experiment '/' name];
end
