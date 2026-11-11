function fig = video_viewer()
% App state

data = Shared.SessionData.instance();
% video export in progress (see saveVideo); not in hd, which holds handles only
exportState = struct('running', false, 'abort', false, 'writer', []);

drawGUI();


function drawGUI()
    % Main UI figure with grid layout
    fig = uifigure('Name', 'KineSync Video', 'Position', Shared.window_position('video', [100 100 600 600]), ...
        'CloseRequestFcn', @onClose);
    data.fig(1).video = fig;
    Shared.MenuBar(fig, {'Open', @openVideo; 'Save', @saveVideo});
    % for dragging markers
    fig.WindowButtonDownFcn   = @(src,evt)onMouseDown(src, evt);
    fig.WindowButtonMotionFcn = @(src,evt)onMouseMove(src, evt);
    fig.WindowButtonUpFcn     = @(src,evt)onMouseUp(src, evt);
    drawnow

    gl = uigridlayout(fig, [3, 2]);
    gl.RowHeight = {30, 40, '1x'};
    gl.ColumnWidth = {'1x', 100};
    gl.Padding = [10 10 10 10];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 8;

    hd = struct();

    % Row 1: frame info
    subgrid1 = uigridlayout(gl, [1 4], 'Padding', [0 0 0 0]);
    subgrid1.ColumnWidth = {'1x', 150, 100, 90};
    subgrid1.Layout.Row = 1; subgrid1.Layout.Column = 1;

        % subgrid1
        hd.info = uilabel(subgrid1, ...
            'Text', 'Info:', 'BackgroundColor','W');

        hd.frameRate = Shared.frame_rate_field(subgrid1);

        hd.time = uieditfield(subgrid1, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueDisplayFormat', 'time: %.3f s', ...
            'ValueChangedFcn', @(src,~)data.setTime(src.Value));

        hd.frame = uieditfield(subgrid1, 'numeric', ...
            'Limits', [1 Inf], ...
            'RoundFractionalValues', true, ...
            'ValueDisplayFormat', 'frame: %d', ...
            'ValueChangedFcn', @manualFrameInput);

    subgrid2 = uigridlayout(gl, [1 2], 'Padding', [0 0 0 0]);
    subgrid2.Layout.Row = 1; subgrid2.Layout.Column = 2;

        hd.last = uibutton(subgrid2, 'Text', '<', ...
            'Tooltip','Ctrl+Click to change step size', ...
            'ButtonPushedFcn', @(src,evt)moveVideoFrame(-1));
        hd.next = uibutton(subgrid2, 'Text', '>', ...
            'Tooltip','Ctrl+Click to change step size', ...
            'ButtonPushedFcn', @(src,evt)moveVideoFrame(1));
    
    % Row 2: slider and play button
    hd.slider = uislider(gl, 'ValueChangedFcn', @sliderMoved);
    hd.slider.Layout.Row = 2; hd.slider.Layout.Column = 1;
    hd.play = uibutton(gl, 'Text', 'Play', 'ButtonPushedFcn', @togglePlay);
    hd.play.Layout.Row = 2; hd.play.Layout.Column = 2;

    % Row 3: axes for video
    ax = uiaxes(gl);
    ax.Layout.Row = 3; ax.Layout.Column = [1 2];
    ax.XTick = []; ax.YTick = [];

    % Timer for playback
    hd.timer = timer('ExecutionMode', 'fixedSpacing', ...
        'Period', 0.02, ...
        'TimerFcn', @timerRunning);

    hd.ax = ax;
    axis(hd.ax, 'image'); axis(hd.ax, 'off');
    hold(hd.ax, "on");

    % add listeners
    hd.timeListener = addlistener(data, 'TimeChanged', @(src, ~)updateVideoTime(src.currentTime));
    hd.infoListener = addlistener(data, 'InfoChanged', @(~,~)onInfoChanged());
    % Pose and behavior changes only redraw markers; the frame is not re-read.
    hd.poseListener = addlistener(data, 'PoseChanged', @(~,~)redrawMarkers());
    hd.behavListener = addlistener(data, 'BehavChanged', @(~,~)redrawMarkers());

    data.video(1).hd = hd;
    notify(data, 'WindowsChanged');
end

function openVideo(~,~)
    if exportState.running, return; end
    hd = data.video.hd;
    [file, path] = uigetfile(fullfile(data.defaultPath, '*.mp4'), 'Open Video file');
    drawnow; figure(fig);
    if isequal(file, 0); return; end
    filename = fullfile(path, file);
    data.rememberPath(filename);
    stop(hd.timer);
    data.video.vid = VideoReader(filename);
    data.video.filename = filename;
    data.video.frameIdx = 1;

    data.video.hd = hd;

    updateInfo();
    updateVideoFrame(1);
    data.setTime(data.video.t(1));
    notify(data, 'InfoChanged');
end

%% === Save: export the video with the markers drawn in ===
% Frames are read in order at native resolution, markers are drawn into the
% pixels (Video.draw_markers) from one snapshot of markerState(), and
% VideoWriter writes MPEG-4 at the session frame rate.
function saveVideo(~,~)
    if exportState.running, return; end
    if ~data.has('video')
        uialert(fig, 'There is no video to save.', 'Save');
        return;
    end
    [range, ok] = Shared.ask_save_range(fig, 'Video');
    if ~ok, return; end
    % frames with a time only (none past the last trigger)
    t = data.video.t(:);
    inside = isfinite(t);
    if ~isempty(range), inside = inside & t >= range(1) & t <= range(2); end
    if ~any(inside)
        uialert(fig, 'No video frames lie in the zoom window.', 'Save');
        return;
    end
    frames = (find(inside, 1):find(inside, 1, 'last'))';

    source = data.video.filename;
    [~, base] = fileparts(source);
    [file, path] = uiputfile('*.mp4', 'Save video', fullfile(data.defaultPath, [base '_KineSync.mp4']));
    drawnow; figure(fig);
    if isequal(file, 0), return; end
    filename = fullfile(path, file);
    if strcmpi(filename, source)
        uialert(fig, 'That is the source video. Choose another name.', 'Save refused');
        return;
    end
    answer = inputdlg('Quality (0 to 100):', 'Video quality', [1 30], {'80'});
    drawnow; figure(fig);
    if isempty(answer), return; end
    quality = str2double(answer{1});
    if ~isscalar(quality) || ~isfinite(quality) || quality < 0 || quality > 100
        uialert(fig, 'The quality must be a number from 0 to 100.', 'Save');
        return;
    end

    state = markerState();
    if ~isempty(state.pose), state.pose.tempX = []; state.pose.tempY = []; end   % committed only
    writer = VideoWriter(filename, 'MPEG-4');
    writer.FrameRate = data.getFrameRate();
    writer.Quality = round(quality);
    data.rememberPath(filename);

    hd = data.video.hd;
    beginExport(hd, writer);
    finish = onCleanup(@()endExport(hd));
    written = 0;
    try
        written = Video.write_marked_video(writer, source, frames, data.video.t, state, ...
            pointScale(hd), @(k, n, img)exportProgress(hd, frames, k, n, img));
    catch ME
        if isvalid(fig), uialert(fig, ME.message, 'Save failed'); end
    end
    if ~isvalid(fig), return; end   % closed during the export: the file is finalized
    aborted = exportState.abort;
    clear finish   % restores the window
    if aborted
        uialert(fig, sprintf('Aborted after %d of %d frames. The partial video is in %s.', ...
            written, numel(frames), filename), 'Save', 'Icon', 'warning');
    elseif written == numel(frames)
        uialert(fig, sprintf('%d frames saved in %s.', written, filename), 'Save', 'Icon', 'success');
    end
end

% Video pixels per screen point: markers look as in the window now.
function s = pointScale(hd)
    vid = data.video.vid;
    pos = getpixelposition(hd.ax);
    screenPerVideo = min(pos(3) / vid.Width, pos(4) / vid.Height);
    s = (96/72) / screenPerVideo;   % 96 screen pixels per inch
end

% Only the abort button stays usable; listeners pause; live markers hide.
function beginExport(hd, writer)
    exportState = struct('running', true, 'abort', false, 'writer', writer);
    stop(hd.timer);
    set([hd.frameRate hd.time hd.frame hd.last hd.next hd.slider], 'Enable', 'off');
    hd.timeListener.Enabled = false;
    hd.infoListener.Enabled = false;
    hd.poseListener.Enabled = false;
    hd.behavListener.Enabled = false;
    % set([hd.timeListener hd.infoListener hd.poseListener hd.behavListener], 'Enabled', 'off');
    for name = {'eventMarker', 'poseMarker', 'poseTempMarker'}
        hideMarker(hd, name{1});
    end
    fig.Pointer = 'watch';
    hd.play.Text = 'Abort (0%)';
end

function endExport(hd)
    exportState.running = false;
    exportState.writer = [];
    if ~isvalid(fig), return; end
    set([hd.frameRate hd.time hd.frame hd.last hd.next hd.slider], 'Enable', 'on');
    hd.timeListener.Enabled = true;
    hd.infoListener.Enabled = true;
    hd.poseListener.Enabled = true;
    hd.behavListener.Enabled = true;
    fig.Pointer = 'arrow';
    hd.play.Text = 'Play';
    onInfoChanged();   % resync: frame, slider and markers at the current time
end

% Progress in the abort button and the slider; a preview every 10 frames.
function ok = exportProgress(hd, frames, k, n, img)
    ok = false;
    if exportState.abort || ~isvalid(fig), return; end
    if mod(k, 5) == 0 || k == n
        hd.play.Text = sprintf('Abort (%d%%)', floor(100 * k / n));
        hd.slider.Value = frames(k);
        if mod(k, 10) == 0 && isfield(hd, 'image') && isgraphics(hd.image)
            hd.image.CData = img(1:min(end, size(hd.image.CData, 1)), 1:min(end, size(hd.image.CData, 2)), :);
        end
        drawnow;   % keeps other windows and the abort button usable
    end
    ok = ~exportState.abort && isvalid(fig);
end

% The title shows the source video.
function updateTitle()
    fig.Name = 'KineSync Video';
    if data.has('video') && isfield(data.video, 'filename')
        fig.Name = ['KineSync Video: ' data.video.filename];
    end
end

%% main == event response callback function
function updateVideoFrame(newFrameIdx)
    if ~data.has('video'), return; end
    hd = data.video.hd;
    frameRate = data.getFrameRate();
    if nargin == 0, newFrameIdx = data.video.frameIdx + 1; end
    lastMatched = find(isfinite(data.video.t),1,'last');
    newFrameIdx = min(lastMatched,max(1,round(newFrameIdx)));
    if newFrameIdx < 1 || newFrameIdx > data.video.numFrames
        stop(hd.timer); hd.play.Text = 'Play'; return;
    end
    % Index is acquisition-frame identity, independent of encoded video time.
    CData = read(data.video.vid, newFrameIdx);

    hd = Shared.myPlot(@image, hd, 'image', hd.ax, CData);
    uistack(hd.image, "bottom")
    frameIdx = newFrameIdx;

    % update Time, Frame, and slider
    hd.frame.Value = frameIdx;
    hd.time.Value = data.video.t(frameIdx);
    hd.slider.Value = frameIdx;
    data.video.frameIdx = frameIdx;
    data.video.hd = hd;

    redrawMarkers();
end

% timeChanged listen function
function updateVideoTime(newTime)
    if ~data.has('video'); return; end  % no video
    
    frameRate = data.getFrameRate();
    requested = Shared.time_to_frame(data.video.t,newTime);
    if requested > data.video.numFrames && strcmp(data.video.hd.timer.Running, 'on')
        stop(data.video.hd.timer); data.video.hd.play.Text = 'Play';
    end
    newFrameIdx = min(data.video.numFrames, max(1, requested));
    if newFrameIdx ~= data.video.frameIdx
        updateVideoFrame(newFrameIdx);
    end
end

function updateInfo()
    if ~data.has('video'); return; end
    hd = data.video.hd;
    data.video.numFrames = data.video.vid.NumFrames;
    data.video.t = data.getFrameTimes(data.video.numFrames);
    frameIdx = min(data.video.frameIdx, find(isfinite(data.video.t),1,'last'));
    % initialize Time, Frame, and slider
    hd.frame.Value = frameIdx;
    hd.time.Value = data.video.t(frameIdx);
    hd.slider.Value = frameIdx;

    % It's slow if opening video for the first time.
    totalFrames = data.video.vid.NumFrames;
    data.video.numFrames = totalFrames;
    data.video.t = data.getFrameTimes(totalFrames);
    lastMatched = find(isfinite(data.video.t),1,'last');

    hd.slider.Limits = [1 max(2,lastMatched)];
    % major ticks are minute marks, while values are still frame#
    tickTimes = data.video.t(1):60:data.video.t(lastMatched);
    hd.slider.MajorTicks = Shared.time_to_frame(data.video.t,tickTimes);
    hd.slider.MajorTickLabels = string(round(tickTimes/60))+"'";
    
    hd.frame.Limits = [1 max(2,lastMatched)];
    
    hd.info.Text = sprintf('Size: %dx%dpx\nFrames: %d', ...
        data.video.vid.Height, data.video.vid.Width, totalFrames);

    data.video.hd = hd;
    updateTitle();
end

% callback function for frame-by-frame buttons
function moveVideoFrame(direction)
    if ~data.has('video'), return; end
    playStep = bitshift(1, length(data.video.hd.next.Text)-1);
    if isempty(fig.CurrentModifier)
        % click without cotrol, move frame forward or backward
        last = find(isfinite(data.video.t),1,'last');
        newFrameIdx = min(last, max(1, data.video.frameIdx + direction * playStep));
        data.setTime(data.video.t(newFrameIdx));
    elseif ismember('control', fig.CurrentModifier)
        % control + click: adjust frame step size
        newStep = bitshift(playStep, direction); % *2 or /2
        if newStep >= 1 && newStep <= 16
            playStep = newStep; 
            textlen = length(dec2bin(playStep));
            data.video.hd.next.Text = repmat('>',1, textlen);
            data.video.hd.last.Text = repmat('<',1, textlen);
        end
    end
end

function sliderMoved(src,~)
    idx = min(find(isfinite(data.video.t),1,'last'),max(1,round(src.Value)));
    data.setTime(data.video.t(idx));
end

function manualFrameInput(~,~)
    hd = data.video.hd;
    frameIdx = min(find(isfinite(data.video.t),1,'last'),round(hd.frame.Value));
    frameRate = data.getFrameRate();
    hd.time.Value = data.video.t(frameIdx);
    data.setTime(hd.time.Value) % notify other modules.
end

function togglePlay(~,~)
    if exportState.running, exportState.abort = true; return; end   % the button reads "Abort"
    if ~data.has('video'), return; end
    hd = data.video.hd;
    if strcmp(hd.play.Text, 'Play')
        hd.play.Text = 'Pause';
        start(hd.timer);
    else
        hd.play.Text = 'Play';
        drawnow
        stop(hd.timer);
    end
end

function timerRunning(~,~)
    if ~data.has('video'), return; end
    playStep = bitshift(1, length(data.video.hd.next.Text)-1);
    last = find(isfinite(data.video.t),1,'last');
    % Advance from the displayed frame; rendering time never skips a step.
    newFrameIdx = min(last, data.video.frameIdx + playStep);
    data.setTime(data.video.t(newFrameIdx));
    if newFrameIdx >= last
        stop(data.video.hd.timer); data.video.hd.play.Text = 'Play';
    end
    drawnow
end

function onInfoChanged()
    if ~data.has('video'), return; end
    updateInfo();
    % the time base may have changed: show the frame at the current time
    updateVideoFrame(Shared.time_to_frame(data.video.t, data.currentTime));
end

% === markers ==============================================================
% All markers on the video are drawn here, from a marker state. The live
% display builds the state from the current pose and behavior data; a video
% export takes one snapshot of it so later edits do not affect the file.

function redrawMarkers()
    if ~data.has('video'), return; end
    drawMarkers(markerState(), data.video.frameIdx);
end

% Collect what the markers need from the pose and behavior modules.
%   state.pose   [] or struct: bodypart, x, y (per frame), tempX, tempY ([] if none)
%   state.events [] or struct: t, x, y (per event), from Behav.current_events
function state = markerState()
    state = struct('pose', [], 'events', []);
    if data.has('pose')
        tablePose = data.pose.table;
        bodypart = data.pose.hd.bodypart.Value;
        d.bodypart = bodypart;
        d.x = tablePose.([bodypart '_x']);
        d.y = tablePose.([bodypart '_y']);
        d.tempX = []; d.tempY = [];
        if ismember('temp_x', tablePose.Properties.VariableNames) && ...
                isfield(data.pose, 'segBodypart') && strcmp(data.pose.segBodypart, bodypart)
            d.tempX = tablePose.temp_x;
            d.tempY = tablePose.temp_y;
        end
        state.pose = d;
    end
    state.events = Behav.current_events(data);
end

% Draw the markers of one frame. Event markers fade with distance in time
% from the frame: alpha = 2/(1+exp(|tEvent - tFrame| / 1 s)).
function drawMarkers(state, frameIdx)
    hd = data.video.hd;
    style = Shared.styles();

    % behavior events
    if ~isempty(state.events) && ~isempty(state.events.t)
        hd = Shared.myPlot(@scatter, hd, 'eventMarker', hd.ax, ...
            state.events.x, state.events.y, ...
            'Marker', 'o', 'MarkerEdgeColor', style.eventColor, ...
            'LineWidth', style.eventWidth, 'HitTest', 'off');
        frameT = data.video.t(frameIdx);
        set(hd.eventMarker, 'AlphaData', eventAlpha(state.events.t, frameT), ...
            'MarkerEdgeAlpha', 'flat', 'Visible', 'on');
    else
        hd = hideMarker(hd, 'eventMarker');
    end

    % Pose: committed marker on top, fix preview below it
    d = state.pose;
    if isempty(d) || frameIdx > numel(d.x)
        hd = hideMarker(hd, 'poseMarker');
        hd = hideMarker(hd, 'poseTempMarker');
    else
        if ~isempty(d.tempX)
            hd = Shared.myPlot(@plot, hd, 'poseTempMarker', hd.ax, ...
                d.tempX(frameIdx), d.tempY(frameIdx), 'o', 'Color', style.posePreviewColor, ...
                'LineWidth', style.poseMarkerWidth, 'HitTest','off');
            hd.poseTempMarker.Visible = 'on';
        else
            hd = hideMarker(hd, 'poseTempMarker');
        end
        hd = Shared.myPlot(@plot, hd, 'poseMarker', hd.ax, ...
            d.x(frameIdx), d.y(frameIdx), '+', 'Color', style.poseMarkerColor, ...
            'LineWidth', style.poseMarkerWidth, 'HitTest','off');
        hd.poseMarker.Visible = 'on';
        uistack(hd.poseMarker, "top")
    end
    data.video.hd = hd;
end

function hd = hideMarker(hd, field)
    if isfield(hd, field) && isgraphics(hd.(field))
        hd.(field).Visible = 'off';
    end
end

function a = eventAlpha(eventT, frameT)
    a = 2 ./ (1 + exp(abs(eventT - frameT)));
end

% drag the markers ==========================
function onMouseDown(~, ~)
    if exportState.running, return; end
    if data.has('pose')
        hd = data.video.hd;
        % begin dragging
        cp = hd.ax.CurrentPoint;   % [x y] in axes data units
        cx = cp(1,1); cy = cp(1,2);
        xlims = hd.ax.XLim;
        ylims = hd.ax.YLim;
        tolx = 0.01 * diff(xlims);
        toly = 0.01 * diff(ylims);
        if (isfield(hd, 'poseMarker') && ...
            hd.poseMarker.Visible && ...
            abs(cx - hd.poseMarker.XData) < tolx && ... 
            abs(cy - hd.poseMarker.YData) < toly)
                drag.marker = hd.poseMarker;
                drag.offsetX = cx - hd.poseMarker.XData;
                drag.offsetY = cy - hd.poseMarker.YData;
                data.video.drag = drag;
        end
        if (isfield(hd, 'poseTempMarker') && ...
            hd.poseTempMarker.Visible && ...
            abs(cx - hd.poseTempMarker.XData) < tolx && ... 
            abs(cy - hd.poseTempMarker.YData) < toly)
                drag.marker = hd.poseTempMarker;
                drag.offsetX = cx - hd.poseTempMarker.XData;
                drag.offsetY = cy - hd.poseTempMarker.YData;
                data.video.drag = drag;
        end
    end
end

function onMouseUp(~, ~)
    if exportState.running, return; end
    hd = data.video.hd;
    % update xy data and finish dragging
    if isfield(data.video, 'drag')
        drag = data.video.drag;
        frameIdx = data.video.frameIdx;

        if isequal(drag.marker, hd.poseMarker)
            bodypart = data.pose.hd.bodypart.Value;
            data.pose.table.([bodypart '_x'])(frameIdx) = drag.marker.XData;
            data.pose.table.([bodypart '_y'])(frameIdx) = drag.marker.YData;
            data.notifyPose('edit', {bodypart});
        elseif isequal(drag.marker, hd.poseTempMarker)
            data.pose.table.temp_x(frameIdx) = drag.marker.XData;
            data.pose.table.temp_y(frameIdx) = drag.marker.YData;
            data.notifyPose('preview');
        end
        data.video = rmfield(data.video, 'drag');
    end
end

function onMouseMove(~, ~)
    if exportState.running, return; end
    hd = data.video.hd;
    cp = hd.ax.CurrentPoint;
    cx = cp(1,1);  cy = cp(1,2);
    xlims = hd.ax.XLim;
    ylims = hd.ax.YLim;
    tolx = 0.01 * diff(xlims);
    toly = 0.01 * diff(ylims);
    
    if ~isfield(data.video, 'drag')
        % not dragging, only change curser
        if data.has('pose') 
            if (isfield(hd, 'poseMarker') && ...
                hd.poseMarker.Visible && ...
                abs(cx - hd.poseMarker.XData) < tolx && ... 
                abs(cy - hd.poseMarker.YData) < toly) ...
                || ...
               (isfield(hd, 'poseTempMarker') && ...
                hd.poseTempMarker.Visible && ...
                abs(cx - hd.poseTempMarker.XData) < tolx && ... 
                abs(cy - hd.poseTempMarker.YData) < toly)
                    fig.Pointer = 'hand';
            else
                    fig.Pointer = 'arrow';
            end
        end
    else
        % dragging
        drag = data.video.drag;
        drag.marker.XData = cx - drag.offsetX;
        drag.marker.YData = cy - drag.offsetY;
    end
end

function onClose(~,~)
    if ~Shared.confirm_close(fig, 'video'), return; end
    Shared.remember_position('video', fig);
    % During an export: finalize the file now. The export loop resumes only
    % after this returns, possibly after Exit all deleted the session.
    if exportState.running
        exportState.abort = true;
        if ~isempty(exportState.writer), close(exportState.writer); end
    end
    hd=data.video.hd;
    % Stop timer
    if isfield(hd, 'timer') && isvalid(hd.timer)
        stop(hd.timer);
    end

    % Clear all the handles, listeners, timer;
    field = fields(hd);
    for k=1:length(field)
        try
            delete(hd.(field{k}))
        catch ME
            disp(field{k})
            disp(hd.(field{k}))
            warning(ME.identifier, '%s', ME.message);
        end
    end

    % Clear data and graphic handles
    data.video = struct();
    % Clear saved figure handle
    data.fig = rmfield(data.fig, 'video');
    delete(fig);  % finally close the GUI
    data.moduleClosed();
end
end