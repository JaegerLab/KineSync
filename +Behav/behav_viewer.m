function fig = behav_viewer()

    data = Shared.SessionData.instance();
    % true while the "pose changed" prompt is open; further PoseChanged
    % events are ignored until the user answers it.
    posePromptPending = false;
    drawGUI()

    function drawGUI()
        hd = struct;
        % Behavior viewer window with uigridlayout
        fig = uifigure('Name', 'KineSync Behavior', 'Position', Shared.window_position('behav', [100 100 1000 500]), ...
            'CloseRequestFcn',@onClose);
        data.fig(1).behav = fig;
        Shared.MenuBar(fig, {'Open', @openBehav; 'Import Pose', @importBodyparts; 'Save', @saveBehav});
        drawnow
        grid1 = uigridlayout(fig, Padding = [20,20,20,20], ...
            ColumnWidth = {'1x', 140}, RowHeight = {30, '1x', 30});

        %% Row 1: pose processing
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0], ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 1));
        subgrid1.ColumnWidth = {'1x', 150,130,130,120,120};
        hd.info = uilabel(subgrid1,'Text',' Info:', 'BackgroundColor','w');
        hd.frameRate = Shared.frame_rate_field(subgrid1);
        hd.resolution = uieditfield(subgrid1,'numeric','Value',30, ...
            'ValueDisplayFormat','Resolution: %d px/cm', ...
            'ValueChangedFcn', @(~,~)updateInfo);
        hd.bodypartThresh = uieditfield(subgrid1,'numeric','Value',10, ...
            'ValueDisplayFormat','Threshold: %.2f cm', ...
            'ValueChangedFcn', @bodypartThreshChanged);
        hd.minTimeInterval = uieditfield(subgrid1,'numeric','Value',0.2, ...
            'ValueDisplayFormat','Min interval: %.2f s', ...
            'Limits', [0 Inf], 'LowerLimitInclusive', 'off', ...
            'ValueChangedFcn', @intervalChanged);
        
        uibutton(subgrid1, 'Text', 'Edit Mask', 'ButtonPushedFcn', @openMask);
        % shares the Min interval cell; shown instead of it for onset/offset
        hd.nearZero = uieditfield(subgrid1,'numeric','AllowEmpty','on','Value',[], ...
            'ValueDisplayFormat','Near-zero: %.2f cm/s', ...
            'Limits', [0 Inf], 'Visible', 'off', ...
            'ValueChangedFcn', @nearZeroChanged);
        hd.nearZero.Layout = hd.minTimeInterval.Layout;

        hd.trace = uidropdown(grid1, 'Items',{'X', 'Y', 'Speed'}, 'Value', 'X', ...
            'ValueChangedFcn', @traceChanged, ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));


        %% Row 2: pose plot
        hd.ax = createAxes(grid1);
        ylabel(hd.ax, 'X (cm)');

        subgrid3 = uigridlayout(grid1, [4 1], Padding = [0 0 0 0], ...
            RowHeight={'1x', 30, '1x', 30});
        subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
        hd.bodypart = uilistbox(subgrid3, 'Multiselect', 'off', ...
            'ValueChangedFcn', @bodypartChanged, 'Enable','off');
        subgrid4 = uigridlayout(subgrid3, [1 2], Padding = [0 0 0 0]);
            hd.eventCheck = uicheckbox(subgrid4, Text='Events', Value=1, ...
                Enable='off', ValueChangedFcn = @eventCheckChanged);
            hd.eventNum = uieditfield(subgrid4, 'numeric', Value = 0, Editable='off', ...
                ValueDisplayFormat = 'n = %d');
        hd.eventList = uilistbox(subgrid3, 'Multiselect', 'off', ...
            'ValueChangedFcn', @eventChanged, 'Enable','off');
        hd.eta = uibutton(subgrid3, Text='Event Triggered Avg', Enable='off', ...
                ButtonPushedFcn=@openETA);

        %% Row 3: zoom in, zoom out, update buttons
        subgrid2 = uigridlayout(grid1, [1 4], 'Padding', [0 0 0 0]);
        subgrid2.Layout.Row = 3; subgrid2.Layout.Column = 2;
        uibutton(subgrid2,'Text','🔍︎+','ButtonPushedFcn',@zoomIn, ...
            'Tooltip','Zoom in');
        uibutton(subgrid2,'Text','🔍︎-','ButtonPushedFcn',@zoomOut, ...
            'Tooltip','Zoom out');
        uibutton(subgrid2,'Text','⭯','ButtonPushedFcn',@refresh, ...
            'Tooltip','Refresh');
        uibutton(subgrid2,'Text','[➜','ButtonPushedFcn',@exportAxes, ...
            'Tooltip','Pop out');

        % add listeners
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateBehavTime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateBehavZoom(src.currentZoom));
        hd.infoListener = addlistener(data, 'InfoChanged', @(~,~)updateInfo());
        hd.maskListener = addlistener(data, 'MaskChanged', @(~,~)updateInfo());
        hd.previewListener = addlistener(data, 'MaskPreviewChanged', @(~,~)previewChanged());
        hd.poseListener = addlistener(data, 'PoseChanged', @(~,evt)onPoseChanged(evt));

        data.behav(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    % plot axes in rows 2-3, column 1 of the main grid
    function ax = createAxes(parent)
        ax = uiaxes(parent); hold(ax, 'on');
        ax.ButtonDownFcn = @axClicked;
        ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        ax.Layout.Row = [2 3]; ax.Layout.Column = 1;
        xlabel(ax, 'Time (s)')
        disableDefaultInteractivity(ax)
    end

    % A right y axis cannot be removed from an axes: replace the axes. The
    % plots are recreated by the next plotTrace/plotEvents.
    function hd = removeRightAxis(hd)
        old = hd.ax;
        hd.ax = createAxes(old.Parent);
        ylabel(hd.ax, old.YAxis(1).Label.String);
        xlim(hd.ax, old.XLim);
        delete(old);
        hd = rmfield(hd, intersect(fieldnames(hd), ...
            {'maskTraceGood', 'maskTraceBad', 'maskTraceThres'}));
    end

    function importBodyparts(~,~)
        hd = data.behav.hd;
        if ~data.has('pose')
            % no pose data, read pose from file.
            [filename, pathname]=uigetfile(fullfile(data.defaultPath, '*.csv'), 'Open DeepLabCut file');
            if isequal(pathname,0), return; end
            filename=fullfile(pathname, filename);
            if ~exist(filename, "file"), return; end
            data.rememberPath(filename);

            tablePose = Pose.align_to_video(Pose.read_pose(filename), fig);
            partList = tablePose.Properties.UserData;
            poseFile = filename;
            source = filename;
        else
            % read pose from pose_viewer
            tablePose = data.pose.table;
            partList = data.pose.hd.bodypart.Items;
            poseFile = '';
            if isfield(data.pose, 'filename'), poseFile = data.pose.filename; end
            source = 'pose_module';  % follow later pose edits (see onPoseChanged)
        end
        
        % select body parts
        [idx, tf] = listdlg('PromptString','Select body parts:','ListString',partList);
        drawnow; figure(fig);
        if ~tf, return; end

        % add selected body parts into GUI lists
        hd.bodypart.Items = partList(idx); hd.bodypart.Enable = 'on';
        hd.bodypart.ItemsData = 1:numel(idx);

        % save raw x, y in pixels, 
        % so that later no need to read from pose when frame rate changes.
        for field = {'maskFig','eta_GUI'}
            if isfield(hd, field{1}) && isgraphics(hd.(field{1})), close(hd.(field{1})); end
        end
        invalidateEvents();
        oldHd = data.behav.hd;
        data.behav = struct('hd', oldHd);
        data.behav.source = source;
        data.behav.filename = poseFile;   % shown in the title
        posePromptPending = false;
        for ii = 1:numel(hd.bodypart.Items) 
            bodypartName = hd.bodypart.Items{ii};
            data.behav.bodypart(ii).name = bodypartName;
            data.behav.bodypart(ii).rawX = tablePose.([bodypartName '_x']);
            data.behav.bodypart(ii).rawY = tablePose.([bodypartName '_y']);
            data.behav.bodypart(ii).thresh = struct('x',NaN,'y',NaN,'speed',NaN,'nearZero',NaN);
        end

        % enable Events
        hd.eventCheck.Enable = 'on';
        hd.eta.Enable = 'on';
        hd.eventList.Enable = 'on';
        hd.eventList.Items = {'rising','falling','onset','offset','peak','valley'};
        hd.eventList.ItemsData = {'rising','falling','onset','offset','peak','valley'};
        hd.eventList.Value = 'rising';

        getSpeeds();
        plotTrace();
        getEvents();
        plotEvents();
        updateTitle();
    end

    % The title shows the behavior file last opened or saved, otherwise the pose
    % file the body parts were imported from.
    function updateTitle()
        fig.Name = 'KineSync Behavior';
        if ~data.has('behav'), return; end
        shown = '';
        if isfield(data.behav, 'filename'), shown = data.behav.filename; end
        if isfield(data.behav, 'displayName'), shown = data.behav.displayName; end
        if ~isempty(shown), fig.Name = ['KineSync Behavior: ' shown]; end
    end

    %% === Save and Open behavior files (Behav.save_behav / Behav.read_behav) ===
    function saveBehav(~,~)
        if ~data.has('behav')
            uialert(fig, 'There is no behavior data to save.', 'Save');
            return;
        end
        [range, ok] = Shared.ask_save_range(fig, 'Behavior');
        if ~ok, return; end
        if ~isfield(data.behav, 'filename'), data.behav.filename = ''; end
        base = 'behav';
        if ~isempty(data.behav.filename), [~, base] = fileparts(data.behav.filename); end
        [file, path] = uiputfile('*.mat', 'Save behavior', fullfile(data.defaultPath, [base '_behav.mat']));
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        % never overwrite the pose input or the behavior file opened
        originals = {data.behav.filename};
        if isfield(data.behav, 'sourceFile'), originals{end+1} = data.behav.sourceFile; end
        if any(strcmpi(filename, originals))
            uialert(fig, sprintf('%s is a file this behavior data was read from. Choose another name.', file), ...
                'Save refused');
            return;
        end
        hd = data.behav.hd;
        syncSelection();
        settings = struct('resolution', hd.resolution.Value, 'minInterval', hd.minTimeInterval.Value);
        Behav.save_behav(filename, data.behav, settings, data.getFrameRate(), range);
        data.rememberPath(filename);
        data.behav.displayName = filename;
        updateTitle();
    end

    % Replace the behavior data with a saved file and recalculate.
    function openBehav(~,~)
        [file, path] = uigetfile(fullfile(data.defaultPath, '*.mat'), 'Open behavior file');
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        try
            g = Behav.read_behav(filename);
        catch ME
            uialert(fig, ME.message, 'Open behavior file');
            return;
        end
        data.rememberPath(filename);

        hd = data.behav.hd;
        for field = {'maskFig','eta_GUI'}
            if isfield(hd, field{1}) && isgraphics(hd.(field{1})), close(hd.(field{1})); end
        end
        invalidateEvents();
        % Follow pose edits again only if the Pose viewer has the same file open.
        source = g.source;
        if strcmp(source, 'pose_module')
            poseFiles = {};
            if data.has('pose') && isfield(data.pose, 'filename'), poseFiles{end+1} = data.pose.filename; end
            if data.has('pose') && isfield(data.pose, 'sourceFile'), poseFiles{end+1} = data.pose.sourceFile; end
            if isempty(g.filename) || ~any(strcmpi(g.filename, poseFiles)), source = filename; end
        end
        data.behav = struct('hd', hd);
        data.behav.source = source;
        data.behav.filename = g.filename;
        data.behav.displayName = filename;
        data.behav.sourceFile = filename;
        data.behav.mask = g.mask;
        if ~isempty(g.maskParam), data.behav.maskParam = g.maskParam; end
        if isfield(g, 'eta') && ~isempty(g.eta), data.behav.eta = g.eta; end
        posePromptPending = false;
        data.behav.bodypart = g.bodypart;

        % widgets
        traces = struct('x', 'X', 'y', 'Y', 'speed', 'Speed');
        hd.bodypart.Items = {g.bodypart.name};
        hd.bodypart.ItemsData = 1:numel(g.bodypart);
        hd.bodypart.Value = g.selection.bodypart;
        hd.bodypart.Enable = 'on';
        hd.trace.Value = traces.(g.selection.trace);
        hd.resolution.Value = g.resolution;
        hd.minTimeInterval.Value = g.minInterval;
        hd.eventList.Items = {'rising','falling','onset','offset','peak','valley'};
        hd.eventList.ItemsData = hd.eventList.Items;
        hd.eventList.Value = g.selection.event;
        hd.eventList.Enable = 'on';
        hd.eventCheck.Value = g.selection.show;
        hd.eventCheck.Enable = 'on';
        hd.eta.Enable = 'on';

        getSpeeds();
        plotTrace();
        getEvents();
        plotEvents();
        updateTitle();

        rate = data.getFrameRate();
        if abs(rate - g.frameRate) > 1e-6 * max(1, g.frameRate)
            uialert(fig, sprintf(['The behavior data was saved at %.4g Hz; the current frame rate is ' ...
                '%.4g Hz. Speeds and event times use the current rate.'], g.frameRate, rate), ...
                'Frame rate differs', 'Icon', 'warning');
        end
    end

    function getSpeeds()
        hd = data.behav.hd;
        data.behav.speedFactor = data.getFrameRate() / hd.resolution.Value;

        for ii = 1:numel(hd.bodypart.Items)    
            bodypart = data.behav.bodypart(ii);

            % convert raw xy (in pixels) to xy (in centimeters)
            data.behav.bodypart(ii).x = bodypart.rawX./hd.resolution.Value;
            data.behav.bodypart(ii).y = bodypart.rawY./hd.resolution.Value;
            
            % calculate speed in cm/s
            data.behav.bodypart(ii).speed = ...
                Behav.smooth_speed(bodypart.rawX, bodypart.rawY, 3) .* ...
                data.behav.speedFactor;

        end
        % reconstruct t
        data.behav.t = data.getFrameTimes(numel(data.behav.bodypart(1).rawX));
    end
   
    function plotTrace()
        hd = data.behav.hd;
        % preview gone: drop the right axis with its mask-trace plots
        if ~hasTracePreview(data.behav.t) && numel(hd.ax.YAxis) > 1
            hd = removeRightAxis(hd);
        end
        hold(hd.ax, 'on');

        % get trace
        idx = hd.bodypart.Value;
        t = data.behav.t;
        traceType = lower(hd.trace.Value);
        trace = data.behav.bodypart(idx).(traceType);

        % get mask
        if isfield(data.behav, 'maskTemp')
            mask = data.behav.maskTemp;
        elseif isfield(data.behav, 'mask')
            mask = data.behav.mask;
        else
            data.behav.mask = true(size(trace));
            mask = data.behav.mask;
        end
        if numel(mask) ~= numel(trace)
            error('behav:maskSize', 'Mask and trace sizes differ.');
        end
        mask = logical(mask(:));
        unmask = ~mask;

        % Always replace both traces, including empty selections.
        unmask = unmask | unmask([1 1:end-1]) | unmask([2:end end]);
        traceUnmask = trace; traceUnmask(~unmask) = NaN;
        traceMask = trace; traceMask(~mask) = NaN;
        style = Shared.styles();
        hd = Shared.myPlot(@plot, hd, 'bodypartUnmask', hd.ax, t, traceUnmask, ...
            'Color', style.unmaskedColor, 'HitTest', 'off');
        hd = Shared.myPlot(@plot, hd, 'bodypartMask', hd.ax, t, traceMask, ...
            'Color', style.maskedColor, 'HitTest', 'off');

        % plot threshold line
        % Preview colors may change; thresholds and events use committed data.
        thresh = selectedThreshold(trace, idx, traceType);
        hd.bodypartThresh.Value = thresh; % restore threhold display.
        hd = Shared.myPlot(@yline, hd, 'bodypartThresLine', hd.ax, ...
                        [], thresh, ...
                        ':', 'Color', style.threshColor, 'HitTest', 'off');

        % time line, at the frame the video shows
        hd = Shared.myPlot(@xline, hd, 'timeline', hd.ax, ...
                        Shared.frame_time(data, data.currentTime), [], ...
                        '-', 'Color', style.timeline, 'HitTest', 'off');

        % trace-threshold part of a mask preview, on the right y axis:
        % trace where good and where bad, and the threshold (Shared.styles)
        if hasTracePreview(t)
            tp = data.behav.maskTempTrace;
            good = logical(tp.good(:));
            bad = ~good;
            bad = bad | bad([1 1:end-1]) | bad([2:end end]);
            traceGood = tp.trace(:); traceGood(~good) = NaN;
            traceBad = tp.trace(:); traceBad(~bad) = NaN;
            yyaxis(hd.ax, 'right'); hold(hd.ax, 'on');
            hd = Shared.myPlot(@plot, hd, 'maskTraceBad', hd.ax, tp.t, traceBad, ...
                'Color', style.maskPreviewBad, 'LineStyle', '-', 'Marker', 'none', 'HitTest', 'off');
            hd = Shared.myPlot(@plot, hd, 'maskTraceGood', hd.ax, tp.t, traceGood, ...
                'Color', style.maskPreviewGood, 'LineStyle', '-', 'Marker', 'none', 'HitTest', 'off');
            hd = Shared.myPlot(@yline, hd, 'maskTraceThres', hd.ax, ...
                [], tp.threshold, '--', 'Color', style.maskPreviewThresh, 'HitTest', 'off');
            ylabel(hd.ax, tp.label);
            hd.ax.YAxis(2).Color = style.maskPreviewGood;
            yyaxis(hd.ax, 'left');
            hd.ax.YAxis(1).Color = style.leftAxisColor;   % yyaxis recolours the left axis
        end

        data.behav.hd = hd;
    end

    function tf = hasTracePreview(t)
        tf = isfield(data.behav, 'maskTempTrace') && ...
            numel(data.behav.maskTempTrace.trace) == numel(t);
    end

    function invalidateEvents()
        wasValid = isfield(data.behav, 'eventsValid') && data.behav.eventsValid;
        data.behav.eventsValid = false;
        hd = data.behav.hd;
        if isfield(hd, 'eventMarker') && isgraphics(hd.eventMarker)
            hd.eventMarker.Visible = 'off';
        end
        hd.eventNum.Value = 0;
        % Other viewers hide their event markers. A successful recalculation
        % publishes again from plotEvents().
        if wasValid, notify(data, 'BehavChanged'); end
    end

    % Copy the live behavior selection into data.behav.selection, so that other
    % viewers (via Behav.current_events) never read the Behavior viewer's UI controls.
    function syncSelection()
        hd = data.behav.hd;
        sel.bodypart = hd.bodypart.Value;
        sel.trace = lower(hd.trace.Value);
        sel.event = hd.eventList.Value;
        sel.show = logical(hd.eventCheck.Value) && isequal(hd.eventCheck.Enable, 'on');
        data.behav.selection = sel;
    end

    function thresh = selectedThreshold(trace, idx, traceType)
        thresh = data.behav.bodypart(idx).thresh.(traceType);
        if isnan(thresh)
            % Same automatic threshold in plot and calculation; independent of preview.
            thresh = mean(trace, 'omitnan');
            if ~isfinite(thresh), thresh = 0; end
        end
    end

    function getEvents()
        invalidateEvents();
        syncSelection();
        hd = data.behav.hd;
        idx = hd.bodypart.Value;
        traceType = lower(hd.trace.Value);
        trace = data.behav.bodypart(idx).(traceType);
        threshold = selectedThreshold(trace, idx, traceType);
        updateEventOptions(traceType);
        nearZero = NaN;
        if strcmp(traceType,'speed')
            nearZero = manualNearZero(idx);
            if isfinite(nearZero)
                status = 'Set by hand. Clear the field to estimate it automatically.';
            else
                [nearZero, restInfo] = Behav.auto_rest_threshold(trace, data.getFrameRate());
                status = ['Automatic: ' restInfo.status '. Type a value to override.'];
            end
            data.behav.bodypart(idx).nearZeroStatus = status;
        end
        data.behav.bodypart(idx).nearZeroThreshold = nearZero;
        interval = max(1, round(hd.minTimeInterval.Value * data.getFrameRate()));
        detectionMask = data.behav.mask & isfinite(data.behav.t);
        events = Behav.detect_events(trace, detectionMask, threshold, interval, nearZero);
        % Commit only after every event type has been calculated successfully.
        fields = fieldnames(events);
        for k = 1:numel(fields)
            data.behav.bodypart(idx).(fields{k}) = events.(fields{k});
        end
        data.behav.bodypart(idx).traceType = traceType;
        data.behav.eventsBodypart = idx;
        data.behav.eventsTrace = traceType;
        data.behav.eventsValid = true;
        updateIntervalField();
    end

    % NaN: estimate automatically
    function value = manualNearZero(idx)
        value = NaN;
        thresh = data.behav.bodypart(idx).thresh;
        if isfield(thresh, 'nearZero') && ~isempty(thresh.nearZero), value = thresh.nearZero; end
    end

    % One cell for the parameter of the selected event: Near-zero for
    % onset/offset, Min interval for peak/valley, unused for rising/falling.
    function updateIntervalField()
        hd = data.behav.hd;
        eventType = hd.eventList.Value;
        isRest = ischar(eventType) && ismember(eventType, {'onset','offset'});
        hd.nearZero.Visible = isRest;
        hd.minTimeInterval.Visible = ~isRest;
        hd.minTimeInterval.Enable = ~(ischar(eventType) && ismember(eventType, {'rising','falling'}));
        if ~isRest || ~data.has('behav'), return; end
        idx = hd.bodypart.Value;
        if ~isfield(data.behav.bodypart, 'nearZeroThreshold'), return; end
        value = data.behav.bodypart(idx).nearZeroThreshold;
        if isfinite(value), hd.nearZero.Value = value; else, hd.nearZero.Value = []; end
        hd.nearZero.FontAngle = 'normal';
        if ~isfinite(manualNearZero(idx)), hd.nearZero.FontAngle = 'italic'; end
        if isfield(data.behav.bodypart, 'nearZeroStatus') && ~isempty(data.behav.bodypart(idx).nearZeroStatus)
            hd.nearZero.Tooltip = data.behav.bodypart(idx).nearZeroStatus;
        end
    end

    function nearZeroChanged(src,~)
        if ~data.has('behav'), return; end
        invalidateEvents();
        value = src.Value;
        if isempty(value), value = NaN; end
        data.behav.bodypart(data.behav.hd.bodypart.Value).thresh.nearZero = value;
        getEvents(); plotEvents();
    end

    function previewChanged()
        if ~data.has('behav'), return; end
        oldAx = data.behav.hd.ax;
        plotTrace();
        % the axes were replaced: redraw the event markers on the new ones
        if data.behav.hd.ax ~= oldAx, plotEvents(); end
    end

    function updateEventOptions(traceType)
        hd = data.behav.hd;
        selected = hd.eventList.Value;
        items = {'rising','falling','peak','valley'};
        if strcmp(traceType,'speed')
            items = {'rising','falling','onset','offset','peak','valley'};
            hd.bodypartThresh.ValueDisplayFormat = 'Threshold: %.2f cm/s';
            ylabel(hd.ax,'Speed (cm/s)');
        else
            hd.bodypartThresh.ValueDisplayFormat = 'Threshold: %.2f cm';
            ylabel(hd.ax,[upper(traceType) ' (cm)']);
        end
        hd.eventList.ItemsData = {};
        hd.eventList.Items = items;
        hd.eventList.ItemsData = items;
        if ismember(selected,items), hd.eventList.Value = selected; else, hd.eventList.Value = 'rising'; end
    end

    % Draw the Behavior viewer's own event markers, then tell the other viewers to redraw
    % theirs from Behav.current_events(data).
    function plotEvents()
        syncSelection();
        hd = data.behav.hd;
        if Behav.events_current(data) && data.behav.selection.show
            idx = data.behav.selection.bodypart;
            eventIdx = data.behav.bodypart(idx).(data.behav.selection.event);
            eventT = data.behav.t(eventIdx);

            % number of events.
            hd.eventNum.Value = length(eventIdx);

            selectedTrace = data.behav.bodypart(idx).(data.behav.selection.trace);
            style = Shared.styles();
            hd = Shared.myPlot(@scatter, hd, 'eventMarker', hd.ax, ...
                            eventT, selectedTrace(eventIdx), ...
                            'Marker', 'o', 'MarkerEdgeColor', style.eventColor, ...
                            'LineWidth', style.eventWidth, 'HitTest', 'off');
            hd.eventMarker.Visible = 'on';
        elseif isfield(hd, 'eventMarker') && isgraphics(hd.eventMarker)
            hd.eventMarker.Visible = 'off';
        end
        data.behav.hd = hd;
        notify(data, 'BehavChanged');
    end

    function openMask(~,~)
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.behav.hd;
        if ~isfield(hd, 'maskFig') || ~isgraphics(hd.maskFig, 'figure')
            % open a new window
            data.behav.hd.maskFig = Behav.mask_GUI(mousePos);
            notify(data, 'WindowsChanged');
        else
            % if window is already open, activate it.
            figure(hd.maskFig)
        end
    end

    function traceChanged(src,~)
        if ~data.has('behav'), return; end
        invalidateEvents();
        hd = data.behav.hd;
        traceType = lower(src.Value);
        switch traceType
            case 'x'
                ylabel(hd.ax, 'X (cm)')
            case 'y'
                ylabel(hd.ax, 'Y (cm)')
            case 'speed'
                ylabel(hd.ax, 'Speed (cm/s)')
        end

        % Recalculate only the selected body part for this trace.
        plotTrace();
        getEvents();
        plotEvents();
    end

    function updateInfo()
        updateTitle();
        if data.has('behav')
            invalidateEvents();
            getSpeeds()
            plotTrace()
            getEvents()
            plotEvents()
        end
    end

    function openETA(~, ~)
        mousePos = get(0, 'PointerLocation');
        hd = data.behav.hd;
        if ~isfield(hd, 'eta_GUI') || ~isgraphics(hd.eta_GUI, 'figure')
            hd.eta_GUI = Behav.eta_GUI(mousePos);
            data.behav.hd = hd;
            notify(data, 'WindowsChanged');
        else
            figure(hd.eta_GUI);
        end
    end

    function bodypartChanged(~,~)
        invalidateEvents();
        plotTrace();
        getEvents();
        plotEvents();
    end

    function bodypartThreshChanged(~,~)
        if ~data.has('behav'), return; end
        invalidateEvents();
        hd = data.behav.hd;

        % save changed value. No more auto value after manually changed
        idx = hd.bodypart.Value;
        traceType = lower(hd.trace.Value);
        data.behav.bodypart(idx).thresh.(traceType) = hd.bodypartThresh.Value;

        % update threhold line
        style = Shared.styles();
        data.behav.hd = Shared.myPlot(@yline, hd, 'bodypartThresLine', hd.ax, ...
                [], hd.bodypartThresh.Value, ...
                ':', 'Color', style.threshColor, 'HitTest', 'off');

        % redo event detection.
        getEvents();
        plotEvents();
    end

    function intervalChanged(~,~)
        if ~data.has('behav'), return; end
        getEvents(); plotEvents();
    end

    function eventChanged(~,~)
        updateIntervalField();
        plotEvents();
    end

    function eventCheckChanged(src,~)
        if ~data.has('behav'), return; end
        if src.Value && ~Behav.events_current(data), invalidateEvents(); return; end
        plotEvents();   % shows or hides markers here and in the other viewers
    end

    % === sync time and zoom ===========
    function axClicked(~,evt)
        data.setTime(evt.IntersectionPoint(1));
    end
    
    function updateBehavTime(currentTime)
        hd = data.behav.hd;
        if data.has('behav')
            set(hd.timeline, 'Value', Shared.frame_time(data, currentTime));
    
            zoomlim = Shared.zoom(get(hd.ax,'xLim'), currentTime, 'pan');
            data.setZoom(zoomlim);
        end
    end
    
    function zoomIn(~, ~)
        hd = data.behav.hd;
        zoomlim = Shared.zoom(get(hd.ax,'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end
    
    function zoomOut(~, ~)
        hd = data.behav.hd;
        zoomlim = Shared.zoom(get(hd.ax,'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end
    
    function axZoomChanged(src,~)
        data.setZoom(src.Limits);
    end

    function refresh(~,~)
        if ~data.has('behav'), return; end
        t = data.behav.t(isfinite(data.behav.t));
        if numel(t)>1, data.setZoom(t([1 end])); end
        ylim(data.behav.hd.ax, 'auto');   % also undo vertical zoom

        updateInfo();
    end

    function exportAxes(~,~)        
        ax = data.behav.hd.ax;
        f = figure();
        ax2 = copyobj(ax, f);
        ax2.Units = 'normalized';
        ax2.Position = [0 0 1 1];
    end
    
    function updateBehavZoom(newZoom)
        hd = data.behav.hd;
        if data.has('behav')
            newZoom(1) = max([0 newZoom(1)]);
            newZoom(2) = min([newZoom(2) max(data.behav.t, [], 'omitnan')]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end
    
    % === follow edits in the Pose viewer ===========
    % Only when the body parts were imported from the Pose viewer. Prompt once on
    % the first relevant change; ignore further changes until answered.
    function onPoseChanged(evt)
        if posePromptPending || ~data.has('behav'), return; end
        if ~isfield(data.behav, 'source') || ~strcmp(data.behav.source, 'pose_module'), return; end
        if ~ismember(evt.Kind, {'open', 'edit', 'commit'}), return; end
        bodypartNames = {data.behav.bodypart.name};
        changed = intersect(evt.Bodyparts, bodypartNames, 'stable');
        if isempty(changed), return; end

        posePromptPending = true;
        if strcmp(evt.Kind, 'open')
            what = 'A new pose file was opened in the Pose viewer.';
        else
            what = sprintf('Pose data changed for: %s.', strjoin(changed, ', '));
        end
        msg = sprintf(['%s\n\nUpdate the behavior body parts from the Pose viewer, or keep the ' ...
            'copy imported earlier?\nUpdate also includes any pose changes made ' ...
            'while this message is open.'], what);
        uiconfirm(fig, msg, 'Pose changed', ...
            'Options', {'Update', 'Keep'}, 'DefaultOption', 1, 'CancelOption', 2, ...
            'Icon', 'question', 'CloseFcn', @onPoseAnswer);
    end

    function onPoseAnswer(~, evt)
        posePromptPending = false;
        if strcmp(evt.SelectedOption, 'Update'), updateBodypartsFromPose(); end
    end

    % Re-copy every imported body part from the current pose table, keeping the
    % thresholds, then recalculate.
    function updateBodypartsFromPose()
        if ~data.has('behav'), return; end
        if ~data.has('pose')
            uialert(fig, 'The Pose viewer has no data. The behavior body parts were kept.', 'Update');
            return;
        end
        tablePose = data.pose.table;
        nOld = numel(data.behav.bodypart(1).rawX);
        missing = {};
        for ii = 1:numel(data.behav.bodypart)
            name = data.behav.bodypart(ii).name;
            if all(ismember({[name '_x'], [name '_y']}, tablePose.Properties.VariableNames))
                data.behav.bodypart(ii).rawX = tablePose.([name '_x']);
                data.behav.bodypart(ii).rawY = tablePose.([name '_y']);
            else
                missing{end+1} = name; %#ok<AGROW>
            end
        end
        notes = {};
        if ~isempty(missing)
            notes{end+1} = sprintf('Not found in the pose data, kept unchanged: %s.', ...
                strjoin(missing, ', '));
        end
        if height(tablePose) ~= nOld
            if ~isempty(missing)
                % body parts of different lengths cannot share one time base
                uialert(fig, sprintf(['The pose data has %d frames, the behavior data %d, and ' ...
                    'some body parts are missing. Import Pose again instead.'], ...
                    height(tablePose), nOld), 'Update failed');
                return;
            end
            % frame count changed: the mask no longer fits, start over
            data.behav.mask = true(height(tablePose), 1);
            if isfield(data.behav, 'maskTemp'), data.behav = rmfield(data.behav, 'maskTemp'); end
            if isfield(data.behav, 'maskTempTrace'), data.behav = rmfield(data.behav, 'maskTempTrace'); end
            notes{end+1} = 'The number of frames changed, so the mask was reset.';
        end
        updateInfo();
        if ~isempty(notes)
            uialert(fig, strjoin(notes, newline), 'Update', 'Icon', 'warning');
        end
    end

    % close function =================================
    function onClose(src,~)
        if ~Shared.confirm_close(fig, 'behav'), return; end
        Shared.remember_position('behav', fig);
        hd = data.behav.hd;

        % Clear data and graphic handles first
        data.behav = struct();
        data.fig = rmfield(data.fig, 'behav');
        
        % Clear all the handles and plots;
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

        notify(data, 'BehavChanged');   % other viewers remove their event markers
        delete(src);  % finally close the GUI
        data.moduleClosed();
    end

end 