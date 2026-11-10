function tablePose = crop_table(tablePose, t, range)
% tablePose = Pose.crop_table(tablePose, t, range)
% Keep the rows (frames) whose time t lies in range = [t1 t2]. Their frame
% numbers are kept in Properties.CustomProperties.FrameIndex, so
% Pose.save_csv writes them to the index column and reopening the file
% puts the rows back on the same frames.

    frames = (1:height(tablePose))';
    if isprop(tablePose.Properties.CustomProperties, 'FrameIndex') && ...
            numel(tablePose.Properties.CustomProperties.FrameIndex) == height(tablePose)
        frames = tablePose.Properties.CustomProperties.FrameIndex(:);
    else
        tablePose = addprop(tablePose, 'FrameIndex', 'table');
    end
    keep = t(:) >= range(1) & t(:) <= range(2);
    tablePose = tablePose(keep, :);
    tablePose.Properties.CustomProperties.FrameIndex = frames(keep);
end
