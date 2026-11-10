function written = write_marked_video(writer, source, frames, t, state, pxPerPoint, progressFcn)
% written = Video.write_marked_video(writer, source, frames, t, state, pxPerPoint, progressFcn)
% Write video frames with markers drawn in (Video.draw_markers).
%   writer       a VideoWriter, not yet open (FrameRate, Quality set); it is
%                opened here and always closed at the end, also on errors
%                or abort, so a partial file stays playable. The caller may
%                also close it to stop (closing the video window).
%   source       video file, read sequentially from frames(1)
%   frames       consecutive frame numbers to write
%   t            time of every frame of the video (s)
%   state        marker snapshot (see Video.draw_markers)
%   progressFcn  @(k, n, img) -> false to stop, called after every frame
%   written      number of frames written
% Odd frame sizes are padded by one row/column for MPEG-4.

    reader = VideoReader(source);
    open(writer);
    closeWriter = onCleanup(@()close(writer));
    reader.CurrentTime = (frames(1) - 1) / reader.FrameRate;
    n = numel(frames);
    written = 0;
    for k = 1:n
        if ~hasFrame(reader), break; end
        img = readFrame(reader);
        img = Video.draw_markers(img, state, frames(k), t(frames(k)), pxPerPoint);
        % repeat the last row / column (no Image Processing Toolbox)
        if mod(size(img, 1), 2), img(end+1, :, :) = img(end, :, :); end %#ok<AGROW>
        if mod(size(img, 2), 2), img(:, end+1, :) = img(:, end, :); end %#ok<AGROW>
        writeVideo(writer, img);
        written = k;
        if ~progressFcn(k, n, img), break; end
    end
end
