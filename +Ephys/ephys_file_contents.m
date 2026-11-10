function [names, bytes] = ephys_file_contents(filename)
% [names, bytes] = Ephys.ephys_file_contents(filename)
% Data variables of an ephys .mat file written by Ephys.save_ephys, without
% loading them: names = {'raw', 'processed1', ...}, bytes = their sizes.
% Errors: ephys:file:format (not a KineSync Ephys file), ephys:file:older
% (an EMG file saved before the ephys rename), ephys:file:newer.

    VERSION = 1;
    [~, name, ext] = fileparts(filename);
    name = [name ext];
    info = whos('-file', filename);
    vars = {info.name};
    if all(ismember({'fileFormat', 'formatVersion', 'emg'}, vars))
        error('ephys:file:older', '%s was saved by an older KineSync (EMG file).', name);
    end
    if ~all(ismember({'fileFormat', 'formatVersion', 'ephys'}, vars))
        error('ephys:file:format', '%s is not a KineSync Ephys file.', name);
    end
    f = load(filename, 'fileFormat', 'formatVersion');
    if ~isequal(f.fileFormat, 'KineSync Ephys')
        error('ephys:file:format', '%s is not a KineSync Ephys file.', name);
    end
    if f.formatVersion > VERSION
        error('ephys:file:newer', '%s was saved by a newer KineSync (format %g; this version reads format %d).', ...
            name, f.formatVersion, VERSION);
    end

    processed = regexp(vars, '^processed(\d+)$', 'tokens', 'once');
    isProcessed = ~cellfun(@isempty, processed);
    numbers = cellfun(@(c)str2double(c{1}), processed(isProcessed));
    [~, order] = sort(numbers);
    idx = find(isProcessed);
    idx = [find(strcmp(vars, 'raw')), idx(order)];
    names = vars(idx);
    bytes = [info(idx).bytes];
end
