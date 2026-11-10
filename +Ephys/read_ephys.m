function data = read_ephys(files)
% Read Open Ephys and convert it to Intan compatible format.
% go to https://github.com/open-ephys/open-ephys-matlab-tools
% for ephys reader installation and documentation.

if ~exist('Session', 'class')
    url = 'https://github.com/open-ephys/open-ephys-matlab-tools';
    fprintf(['Reading Open Ephys data needs open-ephys-matlab-tools (class Session).\n' ...
        'Install it from %s and add it to the MATLAB path.\n'], url);
    msgbox(sprintf(['Reading Open Ephys data needs open-ephys-matlab-tools.\n\n' ...
        'Install it from\n%s\nand add it to the MATLAB path.'], url), ...
        'Open Ephys reader missing', 'warn', 'modal');
    error('ephys:missingReader', 'open-ephys-matlab-tools is not on the MATLAB path.');
end

data = struct();
nodes = dir(fullfile(files, 'Record Node*'));
nodes = nodes([nodes.isdir]);
if isempty(nodes); return; end
nodeIndex = choose({nodes.name}, 'Select record node:');
nodeDir = fullfile(files, nodes(nodeIndex).name);

list = binaryRecordings(nodeDir);
if ~isempty(list)
    % Binary: open only the selected recordings. Session would open them all,
    % and fails on a recording with an empty data file.
    listed = list(~[list.empty]);
    if isempty(listed), error('ephys:emptyRecording', 'All recordings in %s are empty.', nodeDir); end
    prompt = 'Select recordings (joined in time order, gaps kept):';
    if numel(listed) < numel(list)
        prompt = {prompt, sprintf('%d empty recording(s) not listed.', numel(list) - numel(listed))};
    end
    selected = listed(chooseMany({listed.label}, prompt));
    recs = cell(1, numel(selected));
    for k = 1:numel(selected)
        try
            recs{k} = BinaryRecording(selected(k).directory, selected(k).experiment, selected(k).recording);
        catch ME
            error('ephys:openEphys:read', 'Cannot read %s:\n%s', selected(k).name, ME.message);
        end
    end
else
    % other formats: through Session, recordings in folder order (experiment,
    % then recording number); the reader lists recording10 before recording2.
    session = Session(files);
    node = session.recordNodes{nodeIndex};
    recs = node.recordings;
    order = sortrows([cellfun(@(r)folderNumber(r.directory, 2), recs(:)), ...
        cellfun(@(r)folderNumber(r.directory, 1), recs(:)), (1:numel(recs))']);
    recs = recs(order(:,3));
    selected = chooseMany(cellfun(@recordingLabel, recs, 'UniformOutput', false), ...
        'Select recordings (joined in time order, gaps kept):');
    recs = recs(selected);
end
rec = recs{1};
keys = rec.continuous.keys();
streamIndex = choose(keys, 'Select continuous stream:');
keyName = keys{streamIndex};
recording = rec.continuous(keyName);
[samples, data.t, digital] = Ephys.concat_openephys(recs, keyName);

channelNames = recording.metadata.names;
data.sampleRate = recording.metadata.sampleRate;

% get data from analog channels
analogChans = startsWith(channelNames, 'CH');
if any(analogChans)
    data.analogData = samples(:, analogChans);
    data.analogUnits = 'counts';
    data.analogChannels = channelNames(analogChans);
end

% get data from ADC channels
adcChans = startsWith(channelNames, 'ADC');
if any(adcChans)
    data.adcData = samples(:, adcChans);
end
clear samples

% BinaryRecording exposes raw counts. Match the selected stream's metadata.
if strcmpi(rec.format, 'Binary')
    streams = rec.info.continuous;
    folders = cellfun(@(v)regexprep(char(v),'[/\\]+$',''), {streams.folder_name}, 'UniformOutput',false);
    idx = find(strcmp(folders, char(recording.metadata.streamName)),1);
    if isempty(idx), error('ephys:units:stream','Cannot locate scaling metadata for the selected stream.'); end
    channels = streams(idx).channels;
    if any(analogChans)
        data.analogData = Ephys.scale_binary_channels(data.analogData, channels(analogChans), 'uV');
        data.analogUnits = 'uV';
    end
    if any(adcChans)
        data.adcData = Ephys.scale_binary_channels(data.adcData, channels(adcChans), 'V');
        data.adcUnits = 'V';
    end
else
    warning('ephys:units:unscaled','This Open Ephys format has not been calibrated here; displaying raw counts.');
end

% TTL lines as digital channels (see Ephys.ttl_channels); the camera trigger
% is chosen in the Ephys viewer
if ~isempty(digital)
    data.digital = digital;
end

% save files
data.files = files;
end



function list = binaryRecordings(nodeDir)
% Binary-format recordings of a record node, in folder order, without
% reading them: name, label with length, and whether a data file is empty.
list = struct('directory', {}, 'experiment', {}, 'recording', {}, ...
    'name', {}, 'label', {}, 'empty', {});
oebins = dir(fullfile(nodeDir, 'experiment*', 'recording*', 'structure.oebin'));
for k = 1:numel(oebins)
    directory = oebins(k).folder;
    [parent, name] = fileparts(directory);
    [~, experiment] = fileparts(parent);
    info = jsondecode(fileread(fullfile(directory, 'structure.oebin')));
    seconds = NaN;
    empty = isempty(info.continuous);
    for s = 1:numel(info.continuous)
        stream = info.continuous(s);
        dat = dir(fullfile(directory, 'continuous', stream.folder_name, 'continuous.dat'));
        if isempty(dat) || dat.bytes == 0
            empty = true;
        elseif s == 1
            seconds = dat.bytes / (2 * stream.num_channels) / stream.sample_rate;
        end
    end
    list(end+1) = struct('directory', directory, ...
        'experiment', folderNumber(parent, 1), 'recording', folderNumber(directory, 1), ...
        'name', [experiment '/' name], ...
        'label', sprintf('%s/%s (%.1f s)', experiment, name, seconds), 'empty', empty); %#ok<AGROW>
end
if ~isempty(list)
    [~, order] = sortrows([[list.experiment]' [list.recording]']);
    list = list(order);
end
end

function idx = choose(labels,prompt)
if isempty(labels), error('ephys:emptyRecording','No recording sources found.'); end
idx = 1;
if numel(labels)>1
    [idx,ok] = listdlg('PromptString',prompt,'ListString',labels, ...
        'SelectionMode','single','ListSize',[380 200]);
    if ~ok, error('ephys:cancelled','Recording selection cancelled.'); end
end
end

function idx = chooseMany(labels,prompt)
% several items, all selected at first
if isempty(labels), error('ephys:emptyRecording','No recording sources found.'); end
idx = 1;
if numel(labels)>1
    [idx,ok] = listdlg('PromptString',prompt,'ListString',labels, ...
        'SelectionMode','multiple','InitialValue',1:numel(labels),'ListSize',[380 300]);
    if ~ok || isempty(idx), error('ephys:cancelled','Recording selection cancelled.'); end
end
end

function label = recordingLabel(rec)
% experiment1/recording12 (15.2 s), using the first stream for the duration
folder = regexprep(char(rec.directory), '[/\\]+$', '');
[parent, name] = fileparts(folder);
[~, experiment] = fileparts(parent);
label = [experiment '/' name];
keys = rec.continuous.keys();
if ~isempty(keys)
    stream = rec.continuous(keys{1});
    label = sprintf('%s (%.1f s)', label, numel(stream.timestamps)/stream.metadata.sampleRate);
end
end

function n = folderNumber(directory, level)
% trailing number of the folder (level 1) or its parent (level 2)
folder = regexprep(char(directory), '[/\\]+$', '');
for k = 2:level, folder = fileparts(folder); end
[~, name] = fileparts(folder);
n = str2double(regexp(name, '\d+$', 'match', 'once'));
if isnan(n), n = 0; end
end
