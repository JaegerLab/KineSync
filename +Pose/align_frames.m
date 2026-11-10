function [tablePose, how] = align_frames(tablePose, nVideoFrames)
% [tablePose, how] = Pose.align_frames(tablePose, nVideoFrames)
% Put a pose table on the frame grid of the video, using the frame numbers
% read from the file (Properties.CustomProperties.FrameIndex, 1-based).
%   nVideoFrames  frames in the open video, [] without video
%   how           'as is'    rows are frames 1..n already
%                 'shifted'  the video has as many frames as the table (a
%                            video cropped the same way): rows become 1..n
%                 'padded'   NaN rows fill the frames missing from the file,
%                            up to the video length (or the last frame
%                            number without a long enough video)
% Afterwards FrameIndex is 1..height.

    frames = (1:height(tablePose))';
    hasIndex = isprop(tablePose.Properties.CustomProperties, 'FrameIndex') && ...
        ~isempty(tablePose.Properties.CustomProperties.FrameIndex);
    if hasIndex
        frames = tablePose.Properties.CustomProperties.FrameIndex(:);
    else
        tablePose = addprop(tablePose, 'FrameIndex', 'table');
    end
    validateattributes(frames, {'numeric'}, {'vector', 'integer', 'positive', 'numel', height(tablePose)});
    if numel(unique(frames)) ~= numel(frames)
        error('pose:frames:duplicates', 'The pose file has duplicate frame indices.');
    end

    n = height(tablePose);
    if isequal(frames, (1:n)')
        how = 'as is';
    elseif ~isempty(nVideoFrames) && nVideoFrames == n
        how = 'shifted';
    else
        how = 'padded';
        total = max(frames);
        if ~isempty(nVideoFrames), total = max(total, nVideoFrames); end
        if ~all(varfun(@isnumeric, tablePose, 'OutputFormat', 'uniform'))
            error('pose:frames:type', 'Only numeric pose tables can be padded.');
        end
        values = nan(total, width(tablePose));
        values(frames, :) = tablePose{:, :};
        padded = array2table(values, 'VariableNames', tablePose.Properties.VariableNames);
        % body parts, source, scorer
        padded.Properties.UserData = tablePose.Properties.UserData;
        padded.Properties.Description = tablePose.Properties.Description;
        custom = properties(tablePose.Properties.CustomProperties);
        padded = addprop(padded, custom, repmat({'table'}, size(custom)));
        for k = 1:numel(custom)
            padded.Properties.CustomProperties.(custom{k}) = tablePose.Properties.CustomProperties.(custom{k});
        end
        tablePose = padded;
    end
    tablePose.Properties.CustomProperties.FrameIndex = (1:height(tablePose))';
end
