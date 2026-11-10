function tablePose = align_to_video(tablePose, fig)
% tablePose = Pose.align_to_video(tablePose, fig)
% Pose.align_frames against the open video, telling the user in fig when
% the rows were shifted or padded (a pose file cropped to a zoom window).

    data = Shared.SessionData.instance();
    nVideo = [];
    if data.has('video'), nVideo = data.video.numFrames; end
    frames = [];
    if isprop(tablePose.Properties.CustomProperties, 'FrameIndex')
        frames = tablePose.Properties.CustomProperties.FrameIndex;
    end
    [tablePose, how] = Pose.align_frames(tablePose, nVideo);
    if isempty(frames), return; end
    span = sprintf('frames %d to %d', min(frames), max(frames));
    switch how
        case 'shifted'
            uialert(fig, sprintf(['The pose file holds %s. The open video has the same ' ...
                'number of frames, so they are shown as frames 1 to %d.'], span, height(tablePose)), ...
                'Cropped pose file', 'Icon', 'info');
        case 'padded'
            if isempty(nVideo)
                note = 'No video is open: frames before and between them are empty.';
            elseif nVideo < height(tablePose)
                note = sprintf('The open video has only %d frames.', nVideo);
            else
                note = sprintf('Missing frames are empty, up to the video length (%d).', nVideo);
            end
            uialert(fig, sprintf('The pose file holds %s. %s', span, note), ...
                'Cropped pose file', 'Icon', 'info');
    end
end
