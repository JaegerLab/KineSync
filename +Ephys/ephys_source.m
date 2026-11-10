function src = ephys_source(ephysData, label)
% src = Ephys.ephys_source(ephysData, label)
% Data of one ephys type: struct with data (samples x channels), t, sampleRate
% (and parameters for processed data). label: 'Raw' or 'Processed k'.

    if ~any(strcmp(label, Ephys.ephys_types(ephysData)))
        error('ephys:type', 'No ephys data of type "%s".', label);
    end
    if strcmp(label, 'Raw')
        src = ephysData.raw;
    else
        src = ephysData.processed(sscanf(label, 'Processed %d'));
    end
end
