function labels = ephys_types(ephysData)
% labels = Ephys.ephys_types(ephysData)
% Data types in data.ephys, as shown in the Ephys viewer's dropdown:
% 'Raw' if ephysData.raw has data, then 'Processed 1' .. 'Processed N'.

    labels = {};
    if isfield(ephysData, 'raw') && ~isempty(ephysData.raw) && ~isempty(ephysData.raw.data)
        labels{end+1} = 'Raw';
    end
    if isfield(ephysData, 'processed')
        for k = 1:numel(ephysData.processed)
            labels{end+1} = sprintf('Processed %d', k); %#ok<AGROW>
        end
    end
end
