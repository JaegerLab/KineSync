function fig = ephys_viewer()
    % App state
    data = Shared.SessionData.instance();

    drawGUI();

    function drawGUI()
        % Ephys viewer window with uigridlayout
        fig = uifigure('Name', 'KineSync Ephys', 'Position', Shared.window_position('ephys', [100 100 1000 500]), ...
            'CloseRequestFcn', @onClose);
        data.fig(1).ephys = fig;
        Shared.MenuBar(fig, {'Open File', @openFile; 'Open folder', @openFolder; 'Save', @saveEphys});
        drawnow
        grid1 = uigridlayout(fig, ...
            'RowHeight', {30, '1x', 30}, ...
            'ColumnWidth',{'1x', 140});

        hd = struct();

        %% Row 1: Preprocess group
        subgrid1 = uigridlayout(grid1, [1 7], 'Padding', [0 0 0 0]);
        subgrid1.Layout.Row = 1; subgrid1.Layout.Column = 1;
        subgrid1.ColumnWidth = {'1x', 110, 230, 100, 100, 110, 30};
            hd.info = uilabel(subgrid1, 'Text', 'Sample Rate (Hz):');
            hd.sync = uibutton(subgrid1, 'Text', 'Synchronize', 'Enable', 'off', ...
                'ButtonPushedFcn', @synchronize);
            % digital channel shown on the right axis, item 0 shows none
            hd.digital = uidropdown(subgrid1, 'Items', {'No data'}, 'ItemsData', 0, ...
                'Enable', 'off', 'ValueChangedFcn', @(src,evt)drawDigital());
            hd.time = uieditfield(subgrid1,'numeric','Value',0, ...
                    'ValueDisplayFormat', 'time: %.3f s', 'ValueChangedFcn', @timeTyped);
            uibutton(subgrid1, 'Text', 'Pre-Process', 'ButtonPushedFcn', @preprocess);
            % data types: Raw, Processed 1..N (see Ephys.ephys_types)
            hd.datatype = uidropdown(subgrid1, 'Items', {}, 'Placeholder', 'no data', ...
                'ValueChangedFcn', @typeChanged);
            hd.deleteType = uibutton(subgrid1, 'Text', '✕', 'Enable', 'off', ...
                'Tooltip', 'Delete the selected data type', 'ButtonPushedFcn', @deleteType);

        uibutton(grid1, 'Text', 'Load Channel Map', 'ButtonPushedFcn', @(src,evt)loadChannelMap(), ...
            'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 2));

        %% Row 2: Listbox + Axes
        hd.ax = uiaxes(grid1);
        hold(hd.ax, "on");
        hd.ax.ButtonDownFcn = @axClicked;
        hd.ax.Layout.Row = [2 3]; hd.ax.Layout.Column = 1;
        hd.ax.XAxis.LimitsChangedFcn = @(src,evt)axZoomChanged(src,evt);
        xlabel(hd.ax, 'Time (s)'); ylabel(hd.ax, 'Voltage');
        disableDefaultInteractivity(hd.ax)
        % All plots are made here, empty and hidden, and later only get new
        % data: creation order is drawing order. The right axis (digital
        % channel) is always drawn over the left one.
        style = Shared.styles();
        yyaxis(hd.ax, 'right'); hold(hd.ax, 'on');
        hd.digitalPlot = plot(hd.ax, NaN, NaN, '-', 'Color', style.digitalColor, ...
            'Visible', 'off', 'HitTest', 'off', 'Tag', 'digitalPlot');
        hd.ax.YAxis(2).Limits = [-0.1 1.1];
        hd.ax.YAxis(2).TickValues = [0 1];
        hd.ax.YAxis(2).Color = style.digitalColor;
        hd.ax.YAxis(2).Visible = 'off';
        yyaxis(hd.ax, 'left'); hold(hd.ax, 'on');
        hd.ax.YAxis(1).Color = style.leftAxisColor;   % yyaxis recolours the left axis
        % left axis, bottom to top: time line, data, preview, event markers.
        % The time line is a plain line: an xline is always drawn on top.
        % It reaches past any y range and is left out of the axis limits.
        hd.timeline = plot(hd.ax, [0 0], [-1e12 1e12], '-', 'Color', style.timeline, ...
            'XLimInclude', 'off', 'YLimInclude', 'off', ...
            'Visible', 'off', 'HitTest', 'off', 'Tag', 'timeline');
        hd.dataPlot = plot(hd.ax, NaN, NaN, '-', 'Color', style.rawColor, 'Visible', 'off', ...
            'ButtonDownFcn', @axClicked, 'Tag', 'dataPlot');
        hd.tempPlot = plot(hd.ax, NaN, NaN, '-', 'Color', style.previewColor, 'Visible', 'off', ...
            'ButtonDownFcn', @axClicked, 'Tag', 'tempPlot');
        hd.eventMarker = scatter(hd.ax, NaN, NaN, 'Marker', 'o', 'MarkerEdgeColor', style.eventColor, ...
            'LineWidth', style.eventWidth, 'Visible', 'off', 'HitTest', 'off', 'Tag', 'eventMarker');
    
        subgrid3 = uigridlayout(grid1, [2 1], Padding=[0 0 0 0], ...
            RowHeight={'1x', 30});
        subgrid3.Layout.Row = 2; subgrid3.Layout.Column = 2;
            hd.chanList = uilistbox(subgrid3, 'Multiselect', 'off', 'Enable', 'off', ...
                'ValueChangedFcn', @(src,evt)updatePlots());
            subgrid4 = uigridlayout(subgrid3, [1 2], Padding = [0 0 0 0], ...
                        ColumnWidth ={50, '1x'});
            uilabel(subgrid4, 'Text', 'Sort by:');
            hd.sortby = uidropdown(subgrid4, 'Enable', 'off', ...
                "Items",["Channel", "Muscle"], 'ValueChangedFcn', @(src,evt)sortChannelMap());
        

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
        hd.timeListener = addlistener(data, 'TimeChanged', @(src, evt)updateEphysTime(src.currentTime));
        hd.zoomListener = addlistener(data, 'ZoomChanged', @(src, evt)updateEphysZoom(src.currentZoom));
        hd.ephysListener = addlistener(data, 'EphysChanged', @(src, evt)updatePlots());
        hd.behavListener = addlistener(data, 'BehavChanged', @(src, evt)drawEvents());
        hd.InfoListener = addlistener(data, 'InfoChanged', @(src, evt)updateInfo());
        % Synchronize needs frames: follow Video, Pose and Behavior opening and closing
        hd.syncListeners = [ ...
            addlistener(data, 'PoseChanged', @(src, evt)updateSyncEnable()), ...
            addlistener(data, 'BehavChanged', @(src, evt)updateSyncEnable()), ...
            addlistener(data, 'WindowsChanged', @(src, evt)updateSyncEnable())];

        data.ephys(1).hd = hd;
        notify(data, 'WindowsChanged');
    end

    %% === Open a recording folder (Intan or Open Ephys) === %%
    function openFolder(~, ~)
        pathname = uigetdir(data.defaultPath, 'Select the Directory for ephys data files');
        drawnow; figure(fig);
        if isequal(pathname, 0), return; end
        data.rememberPath(pathname);
        loadRecording(@()Ephys.ephys_read(pathname), pathname);
    end

    %% === Open Intan file(s) or a .mat file written by Save === %%
    function openFile(~, ~)
        [files, path] = uigetfile({'*.rhd;*.rhs', 'Intan files (*.rhd, *.rhs)'; ...
                                   '*.mat',       'MAT-files (*.mat)'; ...
                                   '*.*',         'All files (*.*)'}, ...
            'Open Ephys file(s)', data.defaultPath, 'MultiSelect', 'on');
        drawnow; figure(fig);
        if isequal(files, 0), return; end
        files = fullfile(path, cellstr(files));
        % All files lets anything through
        if ~all(endsWith(lower(files), {'.rhd', '.rhs', '.mat'}))
            uialert(fig, 'Select .rhd, .rhs or .mat files.', 'Open File');
            return;
        end
        isMat = endsWith(lower(files), '.mat');
        if any(isMat)
            if numel(files) > 1
                uialert(fig, 'Select a single .mat file, or one or more Intan files.', 'Open File');
                return;
            end
            openMat(files{1});
            return;
        end
        data.rememberPath(files{1});
        displayName = files{1};
        if numel(files) > 1, displayName = path; end
        loadRecording(@()Ephys.read_intan(files), displayName);
    end

    %% === Load a recording read by readFcn, replacing the current ephys data === %%
    function loadRecording(readFcn, displayName)
        hd = data.ephys.hd;
        try
            recording = readFcn();
        catch ME
            drawnow; figure(fig);
            if ismember(ME.identifier, {'ephys:cancelled', 'ephys:missingReader'}), return; end
            % reader checks (e.g. recordings that cannot be joined): tell the user
            if startsWith(ME.identifier, 'ephys:')
                uialert(fig, ME.message, 'Open');
                return;
            end
            rethrow(ME);
        end
        drawnow; figure(fig); % Return from reader dialogs (including Open Ephys TTL selection).

        if isfield(hd, 'prepGUI') && isgraphics(hd.prepGUI), close(hd.prepGUI); end
        % Replace recording-specific state, retaining only the live UI. A new
        % recording needs a new synchronization.
        data.ephys = struct('hd', hd);
        % Update state ---------------
        % reader outputs keep their names; data goes to raw / processed
        data.ephys.filename = recording.files;
        data.ephys.displayName = displayName;
        data.ephys.raw = struct('data', recording.analogData, 't', recording.t, ...
            'sampleRate', recording.sampleRate);
        data.ephys.processed = struct('data', {}, 't', {}, 'sampleRate', {}, 'parameters', {});
        data.ephys.analogChannels = recording.analogChannels;
        data.ephys.analogUnits = 'uV';
        if isfield(recording,'analogUnits'), data.ephys.analogUnits = recording.analogUnits; end
        % digital channels as edge times; one can be shown with hd.digital
        data.ephys.digital = struct('name', {}, 'rise', {}, 'fall', {});
        if isfield(recording, 'digInData')
            % Intan
            names = {};
            if isfield(recording, 'digInChannels')
                names = {recording.digInChannels.native_channel_name};
            end
            data.ephys.digital = Ephys.ttl_channels(recording.t, recording.digInData, names);
        elseif isfield(recording, 'digital')
            % Open Ephys
            data.ephys.digital = recording.digital;
        end

        hd.datatype.Items = Ephys.ephys_types(data.ephys);
        hd.sortby.Enable = 'off';
        hd.chanList.Enable = 'on';

        notify(data, 'InfoChanged');
        notify(data, 'EphysChanged');
        notify(data, 'TimeChanged');
    end

    %% === Open a .mat file written by Save === %%
    % Replaces the current ephys data entirely. Raw data can be left out.
    function openMat(filename)
        try
            [names, bytes] = Ephys.ephys_file_contents(filename);
        catch ME
            uialert(fig, ME.message, 'Open File');
            return;
        end
        if isempty(names)
            uialert(fig, 'The file contains no ephys data.', 'Open File');
            return;
        end
        labels = arrayfun(@(k)sprintf('%s (%.1f MB)', names{k}, bytes(k)/2^20), ...
            1:numel(names), 'UniformOutput', false);
        [selected, ok] = listdlg('Name', 'Open Ephys', 'PromptString', 'Data to load:', ...
            'ListString', labels, 'SelectionMode', 'multiple', ...
            'InitialValue', 1:numel(names), 'ListSize', [260 150]);
        drawnow; figure(fig);
        if ~ok || isempty(selected), return; end
        data.rememberPath(filename);

        hd = data.ephys.hd;
        if isfield(hd, 'prepGUI') && isgraphics(hd.prepGUI), close(hd.prepGUI); end
        ephysData = Ephys.load_ephys(filename, names(selected));
        ephysData.hd = hd;
        ephysData.sourceFile = filename;   % Save may not overwrite it
        ephysData.displayName = filename;
        data.ephys = ephysData;

        types = Ephys.ephys_types(data.ephys);
        hd.datatype.Items = types;
        if ~isempty(types), hd.datatype.Value = types{1}; end
        if isfield(data.ephys, 'chMapping')
            hd.sortby.Items = setdiff(data.ephys.chMapping.Properties.VariableNames, {'Names'}, 'stable');
            hd.sortby.Enable = 'on';
        else
            hd.sortby.Enable = 'off';
        end
        hd.chanList.Enable = 'on';

        notify(data, 'InfoChanged');
        notify(data, 'EphysChanged');
        notify(data, 'TimeChanged');
    end

    %% === Save the selected data types as a .mat file === %%
    function saveEphys(~, ~)
        if ~data.has('ephys')
            uialert(fig, 'There is no ephys data to save.', 'Save');
            return;
        end
        types = Ephys.ephys_types(data.ephys);
        selected = types;
        if numel(types) > 1
            [idx, ok] = listdlg('Name', 'Save Ephys', 'PromptString', 'Data to save:', ...
                'ListString', types, 'SelectionMode', 'multiple', ...
                'InitialValue', 1:numel(types), 'ListSize', [200 120]);
            drawnow; figure(fig);
            if ~ok || isempty(idx), return; end
            selected = types(idx);
        end
        [range, ok] = Shared.ask_save_range(fig, 'Ephys');
        if ~ok, return; end
        [~, base] = fileparts(data.ephys.displayName);
        [file, path] = uiputfile('*.mat', 'Save Ephys', ...
            fullfile(data.defaultPath, [base '_KineSync.mat']));
        drawnow; figure(fig);
        if isequal(file, 0), return; end
        filename = fullfile(path, file);
        if isOriginal(filename)
            uialert(fig, sprintf('%s is the file this ephys data was opened from. Choose another name.', file), ...
                'Save refused');
            return;
        end

        progbar = uiprogressdlg(fig, 'Title', 'Saving', 'Message', 'Saving ephys data', ...
            'Indeterminate', 'on');
        closeBar = onCleanup(@()delete(progbar));   % also on errors
        Ephys.save_ephys(filename, data.ephys, selected, range);
        clear closeBar
        data.rememberPath(filename);
        data.ephys.displayName = filename;   % the title shows the saved file
        updateInfo();
    end

    % true for a file the current ephys data was read from
    function tf = isOriginal(filename)
        originals = {};
        if isfield(data.ephys, 'filename'), originals = cellstr(data.ephys.filename); end
        if isfield(data.ephys, 'sourceFile'), originals{end+1} = data.ephys.sourceFile; end
        tf = any(strcmpi(filename, originals));
    end

    %% === Delete the selected data type === %%
    function deleteType(~, ~)
        hd = data.ephys.hd;
        label = hd.datatype.Value;
        types = Ephys.ephys_types(data.ephys);
        if ~any(strcmp(label, types)), return; end
        if strcmp(label, 'Raw')
            msg = 'Delete the raw ephys data? Only opening the recording again brings it back.';
        else
            msg = sprintf('Delete %s?', label);
        end
        answer = uiconfirm(fig, msg, 'Delete', 'Options', {'Delete', 'Cancel'}, ...
            'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if ~strcmp(answer, 'Delete'), return; end

        idx = find(strcmp(label, types));
        data.ephys = Ephys.ephys_delete(data.ephys, label);
        types = Ephys.ephys_types(data.ephys);
        hd.datatype.Items = types;
        if ~isempty(types) 
            hd.datatype.Value = types{min(idx, end)}; 
        else
            hd.chanList.Enable = 'off';
        end
        notify(data, 'EphysChanged');
        updateInfo();
    end

    % Selected data type, or [] without data.
    function src = currentSource()
        src = [];
        if ~data.has('ephys'), return; end
        types = Ephys.ephys_types(data.ephys);
        label = data.ephys.hd.datatype.Value;
        if ~any(strcmp(label, types)), label = types{1}; end
        src = Ephys.ephys_source(data.ephys, label);
    end

    % Keep the dropdown in step with the data; no deleting while the
    % pre-process window is open.
    function updateTypes()
        hd = data.ephys.hd;
        types = Ephys.ephys_types(data.ephys);
        selected = hd.datatype.Value;
        hd.datatype.Items = types;
        if any(strcmp(selected, types))
            hd.datatype.Value = selected;
        elseif ~isempty(types)
            hd.datatype.Value = types{1};
        end
        prepOpen = isfield(hd, 'prepGUI') && isgraphics(hd.prepGUI);
        hd.deleteType.Enable = ~isempty(types) && ~prepOpen;
    end

    % separate reading and updating info, because reading is slow, and
    % data is saved in SessionData. No need to repeat reading for update.
    function updateInfo()
        if ~isfield(data.ephys, 'hd'), return; end
        updateDigitalList();
        updateSyncEnable();
        if ~data.has('ephys')
            % all data deleted: the metadata (sync) is kept
            if isfield(data.ephys, 'analogChannels'), data.ephys.hd.info.Text = 'No ephys data.'; end
            return;
        end

        hd = data.ephys.hd;

        if data.isSynced()
            s = data.ephys.sync;
            syncInfo = sprintf('Synchronized: %s %s, %d anchors, %.4g Hz', ...
                s.digitalChannelName, s.edge, numel(s.videoAnchor), 1/median(diff(s.syncVideoTime)));
        else
            syncInfo = "Not synchronized.";
        end

        % Update UI -------------------
        fig.Name = ['KineSync Ephys: ' data.ephys.displayName];
        if isfield(data.ephys,'analogUnits'), ylabel(hd.ax,['Ephys (' data.ephys.analogUnits ')']); end
        selectedChannel = hd.chanList.Value;
        if isfield(data.ephys, 'chMapping')
            [~, order] = sort(data.ephys.chMapping.(hd.sortby.Value));
            hd.chanList.Items = data.ephys.chMapping.Names(order);
            hd.chanList.ItemsData = order;
        else
            hd.chanList.Items = data.ephys.analogChannels;
            hd.chanList.ItemsData = 1:length(data.ephys.analogChannels);
        end
        if isnumeric(selectedChannel) && isscalar(selectedChannel) && ...
                ismember(selectedChannel, hd.chanList.ItemsData)
            hd.chanList.Value = selectedChannel;
        end

        % rate and length of the selected data type
        src = currentSource();
        hd.info.Text = sprintf( ...
            'Rate: %g Hz, Length: %.2f s\n%s', ...
            src.sampleRate, src.t(end), ...
            syncInfo);
    end

    %% === Digital channels === %%
    % Items: 'Digital channel:' (0), then one per digital channel. The
    % selection is kept while the channel list stays the same.
    function updateDigitalList()
        hd = data.ephys.hd;
        if ~isfield(data.ephys, 'digital') || isempty(data.ephys.digital)
            label = 'No data';
            if isfield(data.ephys, 'digital'), label = 'No digital channel'; end
            set(hd.digital, 'Items', {label}, 'ItemsData', 0, 'Value', 0, 'Enable', 'off');
        else
            labels = arrayfun(@Ephys.ttl_stats, data.ephys.digital, 'UniformOutput', false);
            selected = hd.digital.Value;
            items = [{'Digital channel:'} labels];
            if ~isequal(hd.digital.Items, items)
                % another recording: nothing shown
                set(hd.digital, 'Items', items, 'ItemsData', 0:numel(labels));
                selected = 0;
            end
            set(hd.digital, 'Value', selected, 'Enable', 'on');
        end
        drawDigital();
    end

    % the selected digital channel as a 0/1 trace on the right axis
    function drawDigital()
        hd = data.ephys.hd;
        k = hd.digital.Value;
        if k == 0 || ~isfield(data.ephys, 'digital') || k > numel(data.ephys.digital)
            hd.digitalPlot.Visible = 'off';
            hd.ax.YAxis(2).Visible = 'off';
            return;
        end
        channel = data.ephys.digital(k);
        [x, y] = digitalTrace(channel.rise, channel.fall);
        set(hd.digitalPlot, 'XData', x, 'YData', y, 'Visible', 'on');
        hd.ax.YAxis(2).Visible = 'on';
        hd.ax.YAxis(2).Label.String = channel.name;
    end

    % step trace from edge times: 0 before the first rise (1 if a fall comes first)
    function [x, y] = digitalTrace(rise, fall)
        edges = sortrows([rise(:) ones(numel(rise),1); fall(:) zeros(numel(fall),1)]);
        if isempty(edges), x = NaN; y = NaN; return; end
        state = edges(:,2);
        before = [1 - state(1); state(1:end-1)];
        tEnd = edges(end,1);
        src = currentSource();
        if ~isempty(src), tEnd = max(tEnd, src.t(end)); end
        x = [min(0, edges(1,1)); reshape([edges(:,1) edges(:,1)]', [], 1); tEnd];
        y = [before(1); reshape([before state]', [], 1); state(end)];
    end

    %% === Synchronization === %%
    % Frames of Video, Pose and Behavior (one timeline) to ephys time, from a
    % digital channel: see Ephys.sync_GUI.
    function synchronize(~, ~)
        hd = data.ephys.hd;
        if ~isfield(hd, 'syncGUI') || ~isgraphics(hd.syncGUI, 'figure')
            hd.syncGUI = Ephys.sync_GUI(get(0, 'PointerLocation'));
            data.ephys.hd = hd;
            notify(data, 'WindowsChanged');
        else
            figure(hd.syncGUI);
        end
    end

    % Synchronize needs digital channels and Video, Pose or Behavior frames.
    function updateSyncEnable()
        if ~isvalid(fig) || ~isfield(data.ephys, 'hd'), return; end
        hasFrames = data.has('video') || data.has('pose') || data.has('behav');
        hasDigital = isfield(data.ephys, 'digital') && ~isempty(data.ephys.digital);
        data.ephys.hd.sync.Enable = hasFrames && hasDigital;
        if ~hasDigital
            data.ephys.hd.sync.Tooltip = 'Needs ephys data with digital channels.';
        elseif ~hasFrames
            data.ephys.hd.sync.Tooltip = 'Needs Video, Pose or Behavior data.';
        else
            data.ephys.hd.sync.Tooltip = 'Synchronize Video/Pose/Behavior frames to ephys time.';
        end
    end

    %% main update
    function updatePlots()
        if ~isfield(data.ephys, 'hd'), return; end
        updateTypes();
        hd = data.ephys.hd;
        drawDigital();
        if ~data.has('ephys')
            set([hd.dataPlot hd.tempPlot hd.timeline], 'Visible', 'off');
            drawEvents();
            return;
        end
        channels = hd.chanList.Value;

        % selected data type: raw or processed color (Shared.styles)
        src = currentSource();
        style = Shared.styles();
        color = style.processedColor;
        if strcmp(hd.datatype.Value, 'Raw'), color = style.rawColor; end
        set(hd.dataPlot, 'XData', src.t, 'YData', src.data(:,channels), ...
            'Color', color, 'Visible', 'on');
        % pre-process preview, over its source
        if isfield(data.ephys, 'temp')
            set(hd.tempPlot, 'XData', data.ephys.temp.t, 'YData', data.ephys.temp.data, ...
                'Visible', 'on');
        else
            hd.tempPlot.Visible = 'off';
        end
        set(hd.timeline, 'XData', [1 1]*frameTime(data.currentTime), 'Visible', 'on');
        drawEvents();
    end

    % behavior events as markers on the ephys trace
    function drawEvents()
        if ~isfield(data.ephys, 'hd'), return; end
        hd = data.ephys.hd;
        events = Behav.current_events(data);
        if data.has('ephys') && ~isempty(events) && ~isempty(events.t) && ...
                ~isempty(hd.chanList.Value)
            src = currentSource();
            y = interp1(src.t, src.data(:,hd.chanList.Value), events.t, 'linear');
            set(hd.eventMarker, 'XData', events.t, 'YData', y, 'Visible', 'on');
        else
            hd.eventMarker.Visible = 'off';
        end
    end

    function loadChannelMap()
        hd = data.ephys.hd;
        if ~isfield(data.ephys, 'analogChannels'), return; end   % nothing opened yet
        nChannels = numel(data.ephys.analogChannels);   % also without raw data
        % select file
        [file, path] = uigetfile(fullfile(data.defaultPath, '*.csv'), ...
            'Select Channel Mapping File', 'MultiSelect', 'off');
        if isequal(path,0), return; end
        drawnow; figure(fig);
        filename = fullfile(path, file);
        if ~exist(filename, "file"), return; end
        data.rememberPath(filename);
        
        % read channel mapping csv file
        chMapping = readtable(filename);
        % check if channel number is correct.
        if height(chMapping) == nChannels
            % mono-pole recording
        elseif height(chMapping) == 2*nChannels
            % differential recording
            chMapping = chMapping(1:2:end, :);
        else
            error('Channel number mismatch');
        end

        % add analog channel name to the mapping table.
        Analog = data.ephys.analogChannels';
        chMapping = addvars(chMapping, Analog, 'before', 1);

        % add variable names to the sort by dropdown menu
        hd.sortby.Items = chMapping.Properties.VariableNames;
        hd.sortby.Enable = 'on';

        % combine table into channel names
        chMapping = convertvars(chMapping, @isnumeric, @(x)cellstr(num2str(x)));
        chMapping.Names = join(chMapping{:,:}, ', ');        
        data.ephys.chMapping = chMapping;

        % save channel names in the list
        hd.chanList.Items = chMapping.Names;
        
        data.ephys.hd = hd;
        sortChannelMap
    end

    function sortChannelMap()
        hd = data.ephys.hd;
        [~, orders] = sort(data.ephys.chMapping.(hd.sortby.Value));
        hd.chanList.Items = data.ephys.chMapping.Names(orders);
        hd.chanList.ItemsData = orders;
    end

    %% pre-process data
    function preprocess(~,~)
        
        % draw new window where the mouse is
        mousePos = get(0, 'PointerLocation');
        hd = data.ephys.hd;

        if ~isfield(hd, 'prepGUI') || ~isgraphics(hd.prepGUI, 'figure')
            hd.prepGUI = Ephys.ephys_prep_GUI(mousePos);
            data.ephys.hd = hd;
            updateTypes();   % no deleting while it is open
            notify(data, 'WindowsChanged');
        else
            % if window is already open, don't open another one.
            figure(hd.prepGUI)
        end
    end

    function typeChanged(~,~)
        % a preview belongs to the type it was made from
        if isfield(data.ephys, 'temp'), data.ephys = rmfield(data.ephys, 'temp'); end
        notify(data, 'EphysChanged');   % redraws; the pre-process window follows the type
        updateInfo
    end

    %% sync figures' time and zoom between windows ========
    % The time line marks the frame shown in Video/Pose/Behavior (Shared.frame_time).
    function t = frameTime(t)
        t = Shared.frame_time(data, t);
    end

    % A typed time moves the cursor; the box then shows the frame time it
    % snapped to (also when that frame is already shown).
    function timeTyped(src, ~)
        data.setTime(src.Value);
        src.Value = frameTime(data.currentTime);
    end

    function axClicked(~,evt)
        data.setTime(evt.IntersectionPoint(1));
    end

    function updateEphysTime(currentTime)
        if data.has('ephys')
            hd = data.ephys.hd;
            cursor = frameTime(currentTime);
            hd.timeline.XData = [1 1]*cursor;
            hd.time.Value = cursor;
            zoomlim = Shared.zoom(data.currentZoom, currentTime, 'pan');
            data.setZoom(zoomlim);
        end
    end

    function zoomIn(~, ~)
        zoomlim = Shared.zoom(get(data.ephys.hd.ax, 'xLim'), data.currentTime, 'in');
        data.setZoom(zoomlim);
    end

    function zoomOut(~, ~)
        zoomlim = Shared.zoom(get(data.ephys.hd.ax, 'xLim'), data.currentTime, 'out');
        data.setZoom(zoomlim);
    end

    function axZoomChanged(src, ~)
        data.setZoom(src.Limits);
    end

    function updateEphysZoom(newZoom)
        hd = data.ephys.hd;
        if data.has('ephys')
            src = currentSource();
            newZoom(1)=max([0 newZoom(1)]);
            newZoom(2)=min([newZoom(2), src.t(end)]);
            if newZoom(2) <= newZoom(1), return; end
            xlim(hd.ax, newZoom);
            data.currentZoom = newZoom;
        end
    end

    function refresh(~,~)
        if ~data.has('ephys'), return; end
        src = currentSource();
        data.setZoom([0 src.t(end)]);
        ylim(data.ephys.hd.ax, 'auto');   % also undo vertical zoom

        updateInfo();
    end

    function exportAxes(~,~)        
        ax = data.ephys.hd.ax;
        f = figure();
        ax2 = copyobj(ax, f);
        ax2.Units = 'normalized';
        ax2.Position = [0 0 1 1];
    end

    % close function
    function onClose(~,~)
        if ~Shared.confirm_close(fig, 'ephys'), return; end
        Shared.remember_position('ephys', fig);
        hd = data.ephys.hd;
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

        % Clear the data
        data.ephys = struct();
        % Clear saved figure handle
        data.fig = rmfield(data.fig, 'ephys');
        delete(fig);  % finally close the GUI
        data.moduleClosed();
    end

end
