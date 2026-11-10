function feedback = save_csv(filename, tablePose)
%SAVE_CSV Write DLC-compatible CSV; absent likelihoods are explicitly unknown.
parts = tablePose.Properties.UserData;
parts = cellstr(string(parts));
parts = parts(~strcmp(parts,'temp'));
if isempty(parts), error('pose:save_csv:parts','No body parts are available to export.'); end
scorer = 'KineSync';
if isprop(tablePose.Properties.CustomProperties,'Scorer') && ...
        ~isempty(tablePose.Properties.CustomProperties.Scorer)
    scorer = char(tablePose.Properties.CustomProperties.Scorer);
end
values = nan(height(tablePose),3*numel(parts));
headers = cell(3,1+size(values,2));
headers(:,1) = {'scorer';'bodyparts';'coords'};
for k = 1:numel(parts)
    part = parts{k}; cols = 3*(k-1)+(1:3);
    names = {[part '_x'],[part '_y'],[part '_likelihood']};
    if ~all(ismember(names(1:2),tablePose.Properties.VariableNames))
        error('pose:save_csv:coordinates','Missing X/Y coordinates for %s.',part);
    end
    values(:,cols(1:2)) = tablePose{:,names(1:2)};
    if ismember(names{3},tablePose.Properties.VariableNames)
        values(:,cols(3)) = tablePose.(names{3});
    end
    headers(1,cols+1) = repmat({scorer},1,3);
    headers(2,cols+1) = repmat({part},1,3);
    headers(3,cols+1) = {'x','y','likelihood'};
end
% index column: zero-based frame numbers (kept by Pose.crop_table)
frames = (1:height(tablePose))';
if isprop(tablePose.Properties.CustomProperties,'FrameIndex') && ...
        numel(tablePose.Properties.CustomProperties.FrameIndex) == height(tablePose)
    frames = tablePose.Properties.CustomProperties.FrameIndex(:);
end
writecell(headers,filename,'Delimiter',',');
writematrix([frames-1 values],filename,'WriteMode','append','Delimiter',',');
feedback = 1;
end
