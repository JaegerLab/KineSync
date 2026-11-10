function save_ephys(filename, ephysData, labels, range)
% Ephys.save_ephys(filename, ephysData, labels, range)
% Write ephys data types to a .mat file (-v7.3):
%   fileFormat = 'KineSync Ephys', formatVersion = 1
%   ephysData          metadata (sync, channels, ...) without data or UI handles;
%                ephysData.timeRange is the saved range ([] for the full length)
%   raw          if 'Raw' is in labels
%   processed1.. the processed types in labels, numbered in that order
% labels: cellstr from Ephys.ephys_types.
% range:  [] (default) for the full length, or [t1 t2]: only samples with
%         t1 <= t <= t2, times unchanged so they stay aligned with the synchronization.

    if nargin < 4, range = []; end
    out = struct();
    out.fileFormat = 'KineSync Ephys';
    out.formatVersion = 1;
    out.ephys = rmfield(ephysData, intersect(fieldnames(ephysData), {'hd', 'temp', 'raw', 'processed'}));
    out.ephys.timeRange = range;
    n = 0;
    for k = 1:numel(labels)
        src = Ephys.ephys_source(ephysData, labels{k});
        if ~isempty(range)
            keep = src.t >= range(1) & src.t <= range(2);
            src.data = src.data(keep, :);
            src.t = src.t(keep);
        end
        if strcmp(labels{k}, 'Raw')
            out.raw = src;
        else
            n = n + 1;
            out.(sprintf('processed%d', n)) = src;
        end
    end
    save(filename, '-struct', 'out', '-v7.3');
end
