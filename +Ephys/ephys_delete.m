function ephysData = ephys_delete(ephysData, label)
% ephysData = Ephys.ephys_delete(ephysData, label)
% Remove one ephys data type ('Raw' or 'Processed k'). The remaining processed
% types are renumbered; metadata (sync, channels, ...) is kept.

    if ~any(strcmp(label, Ephys.ephys_types(ephysData)))
        error('ephys:type', 'No ephys data of type "%s".', label);
    end
    if strcmp(label, 'Raw')
        ephysData = rmfield(ephysData, 'raw');
    else
        ephysData.processed(sscanf(label, 'Processed %d')) = [];
    end
end
