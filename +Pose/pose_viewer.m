function fig = pose_viewer()
    data = Shared.SessionData.instance();

    drawGUI();

    function drawGUI()
        % Pose viewer window with uigridlayout
        fig = uifigure('Name', 'KineSync Pose', 'Position', Shared.window_position('pose', [100 100 1000 500]), ...
            'CloseRequestFcn', @onClose);
        data.fig(1).pose = fig;
        Shared.MenuBar(fig, {'Open', @openPose; 'Save', @savePose});
        drawnow
        grid1 = uigridlayout(fig, [3 2]);
        grid1.Padding = [20,20,20,20];
        grid1.ColumnWidth = {'1x', 140};
        grid1.RowHeight = {30, '1x', 30};

        hd = struct();

        %% Row 1: pose processing
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0], ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 1));
        subgrid1.ColumnWidth = {'1x', 30, 30, 30, 150, 100};
            hd.info = uilabel(subgrid1,'Text',' Info:', 'BackgroundColor','w');
            hd.chkX = uicheckbox(subgrid1,'Text','X','Value',1, ...
                'ValueChangedFcn', @checkXChanged);
            hd.chkY = uicheckbox(subgrid1,'Text','Y','Value',1, ...
                'ValueChangedFcn', @checkYChanged);
            hd.chkP = uicheckbox(subgrid1,'Text','P','Value',0, ...
                'ValueChangedFcn', @checkPChanged);
            hd.frameRate = Shared.frame_rate_field(subgrid1);
            hd.currentFrame = uieditfield(subgrid1,'numeric','Value',1, ...
                'ValueDisplayFormat','Frame: %d');
            
        % subgrid3 = uigridlayout(grid1, [1 2], 'Padding', [0 0 0 0]);
        % subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
        uibutton(grid1,'Text','Pose Fix', 'ButtonPushedFcn',@openFix, ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));
            % hd.manualFix = uicheckbox(subgrid3,'Text','Man. Fix','Value', 0, ...
            %     'ValueChangedFcn',@manualFix);


        %% Row 2: pose plot
        hd.ax = uiaxes(grid1);
        hd.ax.Layout.Row = [2 3]; hd.ax.Layout.Column = 1;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        axis(hd.ax, 'ij'); 
        xlabel(hd.ax, 'Frame'); ylabel(hd.ax, 'Location (pixel)');
        disableDefaultInteractivity(hd.ax);

        hold(hd.ax, 'on');
        hd.ax.ButtonDownFcn = @axClicked;   % clicks on blank space

        subgrid3 = uigridlayout(grid1, [2 1], 'Padding', [0 0 0 0], ...
            'RowHeight', {'1x', 30});
        subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
            hd.bodypart = uilistbox(subgrid3, 'Multiselect', 'off', ...
                'Enable','off', 'ValueChangedFcn', @(src,evt)listChanged());
            hd.deleteBodypart = uibutton(subgrid3, 'Text', 'Delete bodypart', ...
                'Enable', 'off', 'ButtonPushedFcn', @deleteBodypart);

        %% Row 3:  zoom in, zoom out, update buttons
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
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updatePoseTime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updatePoseZoom(src.currentZoom));
        hd.poseListener = addlistener(data, 'PoseChanged', @(src, evt)showBodypart());
        hd.behavListener = addlistener(data, 'BehavChanged', @(src, evt)drawEvents());
        hd.infoListener = addlistener(data, 'InfoChanged', @(src, evt)updateInfo());

        data.pose(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    function openPose(~,~)
        hd = data.pose.hd;
        [filename, pathname]=uigetfile(fullfile(data.defaultPath, '*.csv'), 'Open DeepLabCut file');
        drawnow; figure(fig);
        if isequal(pathname,0), return; end
        filename=fullfile(pathname, filename);
        if ~exist(filename, "file"), return; end
        data.rememberPath(filename);

        % This reading function handles different kinds of data formats
        tablePose = Pose.align_to_video(Pose.read_pose(filename), fig);
        data.pose.table = tablePose;
        data.pose.filename = filename;      % shown in the title; the last saved file
        data.pose.sourceFile = filename;   % Save may not overwrite it
        data.pose.seg = [];
        data.pose.segBodypart = '';

        % update body part list
        hd.bodypart.Enable = 'on';
        hd.bodypart.Items = tablePose.Properties.UserData;
        hd.deleteBodypart.Enable = 'on';

        % axis(hd.ax,'tight');
        % ylim(hd.ax, [0 1200]);
        % xlim(hd.ax, [1 height(tablePose)]);

        data.pose.hd = hd;

        % update frame rate and total frames
        notify(data, 'InfoChanged')
        % draw time line first: it stays below the traces, so clicks reach them
        updatePoseTime(data.currentTime);
        % draw trajectory plot
        data.notifyPose('open', tablePose.Properties.UserData);
    end

    % Save committed body parts as a DLC csv; uncommitted fix previews
    % (temp_*) are left out by Pose.save_csv.
    function savePose(~,~)
        if ~data.has('pose')
            uialert(fig, 'There is no pose data to save.', 'Save');
            return;
        end
        [range, ok] = Shared.ask_save_range(fig, 'Pose');
        if ~ok, return; end
        original = data.pose.filename;
        if isfield(data.pose, 'sourceFile'), original = data.pose.sourceFile; end
        [folder, base] = fileparts(original);
        if ~isempty(data.defaultPath), folder = data.defaultPath; end
        [file, path] = uiputfile('*.csv', 'Save Pose', fullfile(folder, [base '_KineSync.csv']));
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        if strcmpi(filename, original)
            uialert(fig, sprintf('%s is the file this pose data was opened from. Choose another name.', file), ...
                'Save refused');
            return;
        end
        tablePose = data.pose.table;
        if ~isempty(range)
            tablePose = Pose.crop_table(tablePose, data.pose.t, range);
            if height(tablePose) == 0
                uialert(fig, 'No frames lie in the zoom window.', 'Save');
                return;
            end
        end
        Pose.save_csv(filename, tablePose);
        data.rememberPath(filename);
        data.pose.filename = filename;   % the title shows the saved file
        fig.Name = ['KineSync Pose: ' filename];
    end

    function listChanged()
        data.notifyPose('selection');
    end

    % Delete the selected body part from the table (and its fix preview).
    function deleteBodypart(~,~)
        if ~data.has('pose'), return; end
        hd = data.pose.hd;
        bodypart = hd.bodypart.Value;
        items = hd.bodypart.Items;
        if numel(items) < 2
            uialert(fig, 'The only body part cannot be deleted.', 'Delete bodypart');
            return;
        end
        answer = uiconfirm(fig, sprintf('Delete %s?', bodypart), 'Delete bodypart', ...
            'Options', {'Delete', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
            'Icon', 'warning', 'Interpreter', 'none');
        if ~strcmp(answer, 'Delete'), return; end

        if isfield(data.pose, 'segBodypart') && strcmp(data.pose.segBodypart, bodypart)
            temp = intersect({'temp_x', 'temp_y', 'temp_likelihood'}, ...
                data.pose.table.Properties.VariableNames);
            data.pose.table = removevars(data.pose.table, temp);
            data.pose.seg = [];
            data.pose.segBodypart = '';
        end
        cols = intersect(strcat(bodypart, {'_x', '_y', '_likelihood'}), ...
            data.pose.table.Properties.VariableNames);
        data.pose.table = removevars(data.pose.table, cols);
        names = data.pose.table.Properties.UserData;
        data.pose.table.Properties.UserData = names(~strcmp(names, bodypart));

        idx = find(strcmp(items, bodypart));
        items(idx) = [];
        hd.bodypart.Items = items;
        hd.bodypart.Value = items{min(idx, end)};
        data.notifyPose('delete', {bodypart});
    end

    % main update function.=========================
    function showBodypart()
        if ~data.has('pose'); return; end

        hd = data.pose.hd;
        S = Shared.styles();
        
        bodypart = hd.bodypart.Value;

        % update pose plots
        tablePose = data.pose.table;
        t = data.pose.t(:);
        xdata = tablePose.([bodypart '_x']);
        ydata = tablePose.([bodypart '_y']);
        if ismember([bodypart '_likelihood'], tablePose.Properties.VariableNames)
            pdata = tablePose.([bodypart '_likelihood']);
        else
            pdata = nan(size(xdata));
        end

        % update info text
        f = hd.currentFrame.Value;
        hd.info.Text = sprintf( ...
            ['total frames: %d, total time: %.2f\n' ...
            'x=%g, y=%g, p=%.3g'], ...
            length(xdata), max(data.pose.t, [], 'omitnan'), ...
            xdata(f), ydata(f), pdata(f));

        % plot xy plots
        hold(hd.ax, "on");
        % The time line must exist before the traces are created: plot order
        % keeps it below them (no uistack: it fails with yyaxis). Session
        % load draws the traces before TimeChanged, so create it here.
        if ~isfield(hd, 'timelinePose') || ~ishghandle(hd.timelinePose)
            hd = drawTimeline(hd);
        end
        hd = Shared.myPlot(@plot, hd, 'xplot', hd.ax, t, xdata, ...
                '-', 'Color', S.xColor, 'LineWidth', S.trace, ...
                'HitTest', 'on', 'ButtonDownFcn', @axClicked, 'DisplayName', S.legend.x, ...
                'Visible', hd.chkX.Value);

        hd = Shared.myPlot(@plot, hd, 'yplot', hd.ax, t, ydata, ...
                '-', 'Color', S.yColor, 'LineWidth', S.trace, ...
                'HitTest', 'on', 'ButtonDownFcn', @axClicked, 'DisplayName', S.legend.y, ...
                'Visible', hd.chkY.Value);

        set([hd.xplot hd.yplot], 'HitTest', 'on', 'ButtonDownFcn', @axClicked);

        % likelihood on the right y axis
        yyaxis(hd.ax, 'right');
        hd = Shared.myPlot(@plot, hd, 'pplot', hd.ax, t, pdata, ...
                '-', 'Color', S.pColor, 'LineWidth', S.trace, ...
                'HitTest', 'off', 'DisplayName', S.legend.p);
        hd.pplot.Visible = hd.chkP.Value;    % myPlot only sets this on creation
        ylim(hd.ax, [0 1]);                   % ylim([0 1]) alone targets gca, not hd.ax
        hd.ax.YAxis(2).Color = S.pColor;
        hd.ax.YAxis(2).Visible = hd.chkP.Value;

        yyaxis(hd.ax, 'left')
        hd.ax.YAxis(1).Color = S.leftAxisColor;   % yyaxis recolours the left axis

        % fix overlay: only for the body part the segments belong to
        seg = currentSeg(bodypart);
        if isempty(seg)
            hd = setFixVisible(hd, '_x', false);
            hd = setFixVisible(hd, '_y', false);
        else
            hd = drawFix(hd, '_x', t, xdata, tablePose.temp_x, seg, S);
            hd = drawFix(hd, '_y', t, ydata, tablePose.temp_y, seg, S);
            hd = setFixVisible(hd, '_x', hd.chkX.Value);
            hd = setFixVisible(hd, '_y', hd.chkY.Value);

            % % layer order: interpolation behind the trace; jumps, frame
            % % markers and attention circles on top (in that order)
            % uistack([hd.fix_interp_x hd.fix_interp_y], 'bottom');
            % uistack([hd.xplot hd.yplot], 'top');
            % for name = {'jump', 'unflag', 'quest', 'good', 'userGood', 'bad', ...
            %             'userBad', 'attnInterp', 'attnLongBad', 'attnConflict'}
            %     uistack([hd.(['fix_' name{1} '_x']) hd.(['fix_' name{1} '_y'])], 'top');
            % end
            % if isfield(hd, 'timelinePose') && ishghandle(hd.timelinePose)
            %     uistack(hd.timelinePose, 'bottom');
            % end
        end
        data.pose.hd = hd;
        updateLegend(hd);
        drawEvents();
    end

    % behavior events on the X and Y traces (left axis), following the X/Y checkboxes
    function drawEvents()
        if ~isfield(data.pose, 'hd'), return; end
        hd = data.pose.hd;
        events = Behav.current_events(data);
        if data.has('pose') && ~isempty(events) && ~isempty(events.t)
            if numel(hd.ax.YAxis) > 1, yyaxis(hd.ax, 'left'); end
            S = Shared.styles();
            spec = {'Marker', 'o', 'MarkerEdgeColor', S.eventColor, 'LineWidth', S.eventWidth, ...
                'HitTest', 'off', 'HandleVisibility', 'off'};
            hd = Shared.myPlot(@scatter, hd, 'eventX', hd.ax, events.t, events.x, spec{:});
            hd = Shared.myPlot(@scatter, hd, 'eventY', hd.ax, events.t, events.y, spec{:});
            hd.eventX.Visible = hd.chkX.Value;
            hd.eventY.Visible = hd.chkY.Value;
        else
            for field = {'eventX', 'eventY'}
                if isfield(hd, field{1}) && isgraphics(hd.(field{1}))
                    hd.(field{1}).Visible = 'off';
                end
            end
        end
        data.pose.hd = hd;
    end

    % One legend entry per item. Fix layers exist twice (x and y copies with
    % the same DisplayName): use the x copy, or the y copy when x is hidden.
    % Hidden or empty layers are left out.
    function updateLegend(hd)
        S = Shared.styles();
        h = gobjects(0);
        for f = {'xplot', 'yplot', 'pplot'}
            if isfield(hd, f{1}) && isgraphics(hd.(f{1})) && isOn(hd.(f{1}))
                h(end+1) = hd.(f{1}); %#ok<AGROW>
            end
        end
        for name = S.legendOrder
            for sfx = {'_x', '_y'}
                fld = ['fix_' name{1} sfx{1}];
                if isfield(hd, fld) && isgraphics(hd.(fld)) && isOn(hd.(fld)) && ...
                        any(~isnan(hd.(fld).YData))
                    h(end+1) = hd.(fld); %#ok<AGROW>
                    break;
                end
            end
        end
        if isempty(h)
            legend(hd.ax, 'off');
        else
            % AutoUpdate off: objects added later (e.g. event markers) stay out
            legend(hd.ax, h, 'AutoUpdate', 'off', 'Location', S.legendLocation);
        end
    end

    % draw all fix layers for one coordinate (suffix '_x' or '_y')
    function hd = drawFix(hd, sfx, t, v, vfix, seg, S)
        fe   = repelem(seg.flag, seg.len);          % flag per frame
        win  = seg.seedWidth;
        good = fe > 0;
        clickable = {'ButtonDownFcn', @axClicked};
        unclickable = {'HitTest', 'off'};
        % markers sit on the trace: let clicks fall through to it
        passThru  = {'PickableParts', 'none', 'LineStyle', 'none'};
        mk   = [{'MarkerSize', S.markSize, 'LineWidth', S.markWidth}, passThru];
        attn = [{'Marker', S.attnMarker, 'MarkerSize', S.attnSize, 'LineWidth', S.attnWidth}, passThru];

        % interpolation where it replaces data, joined to the good frames
        show = ~good;
        show = show | [show(2:end); false] | [false; show(1:end-1)];
        Y = vfix(:); Y(~show) = NaN;
        hd = Shared.myPlot(@plot, hd, ['fix_interp' sfx], hd.ax, t, Y, ...
            S.interpStyle, 'Color', S.interpColor, 'LineWidth', S.interpWidth, unclickable{:}, ...
            'DisplayName', S.legend.interp);

        % jumps (all, including conflicts): thin dashed, on top of the trace
        [X, Y] = jumpXY(t, v, seg, true(numel(seg.start) - 1, 1));
        hd = Shared.myPlot(@plot, hd, ['fix_jump' sfx], hd.ax, nonEmpty(X), nonEmpty(Y), ...
            S.jumpStyle, 'Color', S.jumpColor, 'LineWidth', S.jumpWidth, clickable{:}, ...
            'DisplayName', S.legend.jump);

        % frame markers (seeds from the algorithm are not marked)
        userGood = repelem(seg.flag == 2 & ~(seg.len >= win), seg.len);  % seed it would not have made
        layers = { ...
            'good',     fe == 1,  S.goodMarker,     S.good, 'none'; ...
            'userGood', userGood, S.userGoodMarker, S.good, S.good; ...
            'bad',      fe == -1, S.badMarker,      S.bad,  'none'; ...
            'quest',    fe == -2, S.questMarker,    S.grey, 'none'; ...
            'userBad',   fe == -3, S.userBadMarker,   S.bad,  'none'; ...
            'unflag',   fe == 0,  S.unflagMarker,   S.grey, 'none'};
        for i = 1:size(layers, 1)
            sel = layers{i, 2};
            hd = Shared.myPlot(@plot, hd, ['fix_' layers{i, 1} sfx], hd.ax, ...
                nonEmpty(t(sel)), nonEmpty(v(sel)), layers{i, 3}, ...
                'Color', layers{i, 4}, 'MarkerFaceColor', layers{i, 5}, mk{:}, ...
                'DisplayName', S.legend.(layers{i,1}));
        end

        % --- needs attention: large circles at both ends --------------------
        % neighbouring good segments: the two frames of the jump between them
        a = seg.stop([seg.conflict(:); false]);
        f = [a; a + 1];
        hd = Shared.myPlot(@plot, hd, ['fix_attnConflict' sfx], hd.ax, ...
            nonEmpty(t(f)), nonEmpty(v(f)), 'Color', S.attnConflict, attn{:}, ...
            'DisplayName', S.legend.attnConflict);
        % long segments the algorithm flagged bad (likely mis-flagged)
        k = find((seg.flag == -1 | seg.flag == -2) & seg.len >= S.longBadFrac * win);
        f = [seg.start(k); seg.stop(k)];
        hd = Shared.myPlot(@plot, hd, ['fix_attnLongBad' sfx], hd.ax, ...
            nonEmpty(t(f)), nonEmpty(v(f)), 'Color', S.attnLongBad, attn{:}, ...
            'DisplayName', S.legend.attnLongBad);
        % long interpolation with no good frame inside: ends of the stretch
        d = diff([false; ~good; false]);
        rs = find(d == 1); re = find(d == -1) - 1;
        long = (re - rs + 1) >= S.longInterpFrac * win;
        f = [rs(long); re(long)];
        hd = Shared.myPlot(@plot, hd, ['fix_attnInterp' sfx], hd.ax, ...
            nonEmpty(t(f)), nonEmpty(vfix(f)), 'Color', S.attnInterp, attn{:}, ...
            'DisplayName', S.legend.attnInterp);
    end

    % show/hide all fix layers of one coordinate; segment labels and
    % attention signs also follow the Pose auto fix checkboxes (fixShow)
    function hd = setFixVisible(hd, sfx, trueFalse)
        S = Shared.styles();
        show = struct('labels', true, 'attn', true);
        if isfield(data.pose, 'fixShow'), show = data.pose.fixShow; end
        f = fieldnames(hd);
        f = f(strncmp(f, 'fix_', 4) & endsWith(f, sfx));
        for i = 1:numel(f)
            if ~ishghandle(hd.(f{i})), continue; end
            name = f{i}(5:end-numel(sfx));
            on = trueFalse;
            if ismember(name, S.labelLayers), on = on && show.labels; end
            if ismember(name, S.attnLayers),  on = on && show.attn;   end
            hd.(f{i}).Visible = on;
        end
    end

    % segment structure of the current fix, if it belongs to this body part
    function seg = currentSeg(bodypart)
        seg = [];
        if ~data.has('pose') || ~isfield(data.pose, 'seg') || isempty(data.pose.seg)
            return;
        end
        if ~isfield(data.pose, 'segBodypart') || ~strcmp(data.pose.segBodypart, bodypart)
            return;
        end
        if ~ismember('temp_x', data.pose.table.Properties.VariableNames) || ...
                data.pose.seg.nFrames ~= height(data.pose.table)
            return;
        end
        seg = data.pose.seg;
    end

    % checkbox callback
    function checkXChanged(src,~)
        hd = data.pose.hd;
        if isfield(hd, 'xplot') && ishghandle(hd.xplot)
            hd.xplot.Visible = src.Value;
        end
        hasFix = ~isempty(currentSeg(hd.bodypart.Value));
        hd = setFixVisible(hd, '_x', src.Value && hasFix);
        data.pose.hd = hd;
        updateLegend(hd);
        drawEvents();
    end
    function checkYChanged(src,~)
        hd = data.pose.hd;
        if isfield(hd, 'yplot') && ishghandle(hd.yplot)
            hd.yplot.Visible = src.Value;
        end
        hasFix = ~isempty(currentSeg(hd.bodypart.Value));
        hd = setFixVisible(hd, '_y', src.Value && hasFix);
        data.pose.hd = hd;
        updateLegend(hd);
        drawEvents();
    end

    function checkPChanged(src,~)
        hd = data.pose.hd;
        if isfield(hd, 'pplot') && ishghandle(hd.pplot)
            hd.pplot.Visible = src.Value;
            hd.ax.YAxis(2).Visible = src.Value;
            updateLegend(hd);
        end
    end

    function updateFrameRate(frameRate)
        hd = data.pose.hd;
        totalFrame = height(data.pose.table);
        data.pose.t = data.getFrameTimes(totalFrame);

        showBodypart();            % redraw trace and fix layers on new time base

        % update xlims if it's out of bound
        xlims = xlim(hd.ax);
        xlims = [max(xlims(1), data.pose.t(1)) min(xlims(2), max(data.pose.t, [], 'omitnan'))];
        if xlims(2) > xlims(1), xlim(hd.ax, xlims); end
        
        if frameRate == 1
            xlabel(hd.ax, 'Frame')
        else
            xlabel(hd.ax, 'Time (s)')
        end
    end

    % triggered by info event
    function updateInfo()
        if ~data.has('pose'), return; end
        hd = data.pose.hd;
        if isfield(data.pose, 'filename')
            fig.Name = ['KineSync Pose: ' data.pose.filename];
        end

        % collect info
        frameRate = data.getFrameRate();
        totalFrame = height(data.pose.table);
        data.pose.t = data.getFrameTimes(totalFrame);

        currentFrame = Shared.time_to_frame(data.pose.t, data.currentTime);
        currentFrame = min(totalFrame, max(1, currentFrame));
        hd.currentFrame.Value = currentFrame;

        updateFrameRate(frameRate);
    end

    function openFix(~,~)
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.pose.hd;
        if ~isfield(hd, 'fixGUI') || ~isgraphics(hd.fixGUI, 'figure')
            % open a new window
            hd.fixGUI = Pose.pose_fix_GUI(mousePos);
            data.pose.hd = hd;
            notify(data, 'WindowsChanged');
        else
            % if window is already open, activate it.
            figure(hd.fixGUI)
        end
    end

    % === sync time and zoom ===========
    % click (anywhere): set time
    % ctrl-click on a line:  add / remove the jump between the two frames
    % shift-click on a line: toggle the segment good (seed) / bad (userBad)
    function axClicked(src,evt)
        clickType = get(fig, 'SelectionType');

        if isequal(clickType, "normal")
            % direct click, change time.
            data.setTime(evt.IntersectionPoint(1));
            return;
        end
        % edits only when a plotted line was hit, not blank space
        if ~(isprop(src, 'Type') && strcmp(src.Type, 'line')), return; end

        hd = data.pose.hd;
        % the P trace is for reference only: no edits from it
        if isfield(hd, 'pplot') && isequal(src, hd.pplot), return; end
        bodypart = hd.bodypart.Value;
        seg = currentSeg(bodypart);
        if isempty(seg), return; end        % no fix preview for this body part

        t  = data.pose.t(:);
        tc = evt.IntersectionPoint(1);
        if isequal(clickType, "alt")
            % ctrl-click: toggle jump
            seg = Pose.pose_seg_toggle_jump(seg, jumpAtClick(src, tc, t, seg, hd));
        elseif isequal(clickType, "extend")
            % shift-click: toggle segment, userBad until changed again
            [~, f] = min(abs(t - tc));
            k = find(seg.start <= f & seg.stop >= f, 1);
            if seg.flag(k) > 0
                seg.flag(k) = -3;
            else
                seg.flag(k) = 2;
            end
            seg.isNew(k) = true;
        else
            return;                         % e.g. double-click
        end

        % recheck only around the edit
        xdata = data.pose.table.([bodypart '_x']);
        ydata = data.pose.table.([bodypart '_y']);
        [tempX, tempY, mask, seg] = Pose.pose_fix(xdata, ydata, [], [], seg);

        data.pose.table.temp_x = tempX;
        data.pose.table.temp_y = tempY;
        data.pose.table.temp_likelihood = Pose.seg_likelihood(seg);
        data.pose.seg = seg;
        data.notifyPose('preview');
    end

    % frame at such that the clicked jump lies between frames a and a+1
    function a = jumpAtClick(src, tc, t, seg, hd)
        S = Shared.styles();
        isJumpLine = isprop(src, 'Tag') && startsWith(src.Tag, 'fix_jump');
        xl = xlim(hd.ax);
        tol = S.snapPx * diff(xl) / max(1, hd.ax.InnerPosition(3));
        a = snapJump(tc, t, seg.stop(1:end-1), tol, isJumpLine);
    end

    function updatePoseTime(currentTime)
        if data.has('pose')
            hd = data.pose.hd;
            currentFrame = Shared.time_to_frame(data.pose.t, currentTime);
            hd.currentFrame.Value = currentFrame;

            % update info text
            bodypart = hd.bodypart.Value;
            tablePose = data.pose.table;
            xdata = tablePose.([bodypart '_x']);
            ydata = tablePose.([bodypart '_y']);
            if ismember([bodypart '_likelihood'], tablePose.Properties.VariableNames)
                pdata = tablePose.([bodypart '_likelihood']);
            else
                pdata = nan(size(xdata));
            end
            f = hd.currentFrame.Value;
            hd.info.Text = sprintf( ...
                ['total frames: %d, total time: %.2f\n' ...
                'x=%g, y=%g, p=%.3g'], ...
                length(xdata), max(data.pose.t, [], 'omitnan'), ...
                xdata(f), ydata(f), pdata(f));

            hd = drawTimeline(hd);
            data.pose.hd = hd;

            data.setTime(currentTime);
    
            % if time is out of current lims, move the zoom frame over.
            zoomlim = Shared.zoom(get(hd.ax,'xLim'), currentTime, 'pan');
            data.setZoom(zoomlim);
        end
    end

    % time line on the left side (see showBodypart). A plain line, not an
    % xline: an xline is always drawn on top. It reaches past any y range and
    % is left out of the axis limits.
    function hd = drawTimeline(hd)
        if isfield(hd, 'timelinePose') && isgraphics(hd.timelinePose)
            hd.timelinePose.XData = [1 1]*data.currentTime;
            return;
        end
        if numel(hd.ax.YAxis) > 1, yyaxis(hd.ax, 'left'); end
        S = Shared.styles();
        hd.timelinePose = plot(hd.ax, [1 1]*data.currentTime, [-1e12 1e12], '-', 'Color', S.timeline, ...
            'XLimInclude', 'off', 'YLimInclude', 'off', 'HitTest', 'off', 'HandleVisibility', 'off', ...
            'Tag', 'timelinePose');
    end

    function zoomIn(~, ~)
        zoomlim = Shared.zoom(get(data.pose.hd.ax,'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end

    function zoomOut(~, ~)
        zoomlim = Shared.zoom(get(data.pose.hd.ax,'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end

    % callback function for axis zoom change
    function axZoomChanged(src,~)
        data.setZoom(src.Limits);
    end

    % response function for zoomChanged listener
    function updatePoseZoom(newZoom)
        if data.has('pose')
            newZoom(1) = max([0 newZoom(1)]);
            newZoom(2) = min([newZoom(2) max(data.pose.t, [], 'omitnan')]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(data.pose.hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end

    function refresh(~,~)
        if ~data.has('pose'), return; end
        finiteTime = data.pose.t(isfinite(data.pose.t));
        if numel(finiteTime)>1, data.setZoom(finiteTime([1 end])); end
        ylim(data.pose.hd.ax, 'auto');   % also undo vertical zoom

        updateInfo();
    end

    function exportAxes(~,~)        
        ax = data.pose.hd.ax;
        f = figure();
        ax2 = copyobj(ax, f);
        ax2.Units = 'normalized';
        ax2.Position = [0 0 1 1];
    end

    % close function =================================
    function onClose(src,~)
        if ~Shared.confirm_close(fig, 'pose'), return; end
        Shared.remember_position('pose', fig);
        hd=data.pose.hd;
        % close fix GUI first.
        if isfield(hd, 'fixGUI') && isgraphics(hd.fixGUI)
            close(hd.fixGUI)
        end
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
    
        % Clear data and graphic handles
        data.pose = struct();
        % Clear saved figure handle
        data.fig = rmfield(data.fig, 'pose');
        data.notifyPose('close');   % e.g. the video viewer hides its pose markers
        delete(src);  % finally close the GUI
        data.moduleClosed();
    end
end

% ==========================================================================
% local helpers (no shared state)
% ==========================================================================
function tf = isOn(h)
% Visible is 'on'/'off' or an OnOffSwitchState depending on MATLAB version
tf = strcmp(char(h.Visible), 'on');
end

function v = nonEmpty(v)
% plot() needs at least one point to return a line handle; NaN draws nothing.
if isempty(v), v = NaN; end
end

% function [X, Y] = segXY(t, v, seg, sel)
% % Points of the selected segments, NaN-separated so that neighbouring
% % segments are never joined across a jump.
% k = find(sel);
% n = sum(seg.len(k)) + numel(k);
% X = nan(n, 1); Y = X;
% p = 1;
% for i = k'
%     r = seg.start(i):seg.stop(i);
%     m = numel(r);
%     X(p:p+m-1) = t(r);
%     Y(p:p+m-1) = v(r);
%     p = p + m + 1;
% end
% end

function [X, Y] = jumpXY(t, v, seg, sel)
% Line pieces from the last frame before each selected jump to the first
% frame after it, NaN-separated.
a = seg.stop([sel(:); false]);          % jump k lies after frame seg.stop(k)
X = [t(a) t(a+1) nan(numel(a), 1)]';
Y = [v(a) v(a+1) nan(numel(a), 1)]';
X = X(:); Y = Y(:);
end

function a = snapJump(tc, t, J, tol, forceSnap)
% Frame interval under the click (jump after frame a), snapped to an
% existing jump J if one lies within tol (or the jump line itself was hit).
N = numel(t);
a = find(t <= tc, 1, 'last');
if isempty(a), a = 1; end
a = min(max(a, 1), N - 1);
if ~isempty(J)
    ctr = (t(J) + t(J + 1)) / 2;
    [dmin, j] = min(abs(ctr - tc));
    if forceSnap || dmin <= tol
        a = J(j);
    end
end
end

