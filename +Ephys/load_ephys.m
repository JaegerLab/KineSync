function ephysData = load_ephys(filename, names)
% ephysData = Ephys.load_ephys(filename, names)
% Read an ephys .mat file written by Ephys.save_ephys, loading only the data
% variables in names (from Ephys.ephys_file_contents). Returns data.ephys without
% UI handles: the metadata, raw (if loaded) and processed (in file order).

    f = load(filename, 'ephys', names{:});
    ephysData = f.ephys;
    % files saved before ephys.sync may hold the obsolete camera trigger
    if isfield(ephysData, 'trigger'), ephysData = rmfield(ephysData, 'trigger'); end
    if isfield(f, 'raw')
        ephysData.raw = struct('data', f.raw.data, 't', f.raw.t, 'sampleRate', f.raw.sampleRate);
    end
    ephysData.processed = struct('data', {}, 't', {}, 'sampleRate', {}, 'parameters', {});
    for k = 1:numel(names)
        if ~startsWith(names{k}, 'processed'), continue; end
        p = f.(names{k});
        ephysData.processed(end+1) = struct('data', p.data, 't', p.t, ...
            'sampleRate', p.sampleRate, 'parameters', p.parameters);
    end
end
