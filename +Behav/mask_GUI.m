function maskFig = mask_GUI(mousePos)
% Create mask-rule controls in an existing uifigure.
% Rule table variables:
%   ID          - Stable uint64 rule identifier
%   Enabled     - Whether the rule is active
%   FromTime    - Inclusive start time
%   ToTime      - Exclusive end time
%   Value       - T/F Logical value assigned by the rule
%
% Rule semantics:
%   Rules are applied from top to bottom. Later rules override earlier
%   rules in overlapping intervals.


    %% State

    state = struct;
    
    state.Rules = table( ...
        uint64.empty(0,1), ...
        logical.empty(0,1), ...
        double.empty(0,1), ...
        double.empty(0,1), ...
        logical.empty(0,1), ...
        'VariableNames', ...
        {'ID','Enabled','FromTime','ToTime','Value'});

    state.SelectedRow = NaN;
    state.NextRuleID  = uint64(1);

    % Trace: any per-frame or timestamped quantity to threshold, e.g. a
    % body-part X, Y or speed, or an Ephys digital channel.
    %   TraceTime   - empty (one value per behavior frame) or sample times
    %   TraceUnits  - shown in the plot; 'pixels/frame' is converted to cm/s
    %   TraceInterp - 'linear' for sampled data, 'previous' for step data
    %                 (digital channels: each value holds until the next)
    state.Trace = double.empty(0,1);
    state.TraceTime = double.empty(0,1);
    state.TraceSource = "";
    state.TraceUnits = '';
    state.TraceInterp = 'linear';
    state.SmoothEnabled = false;
    state.SmoothWindow = 1;
    state.TraceOperator = '>';
    state.TraceThreshold = 0;
    state.ImportSource = 'from Behavior';

    defaultState = state;

    importSources = {'from Behavior', 'from Pose', 'from Ephys', ...
        'from File', 'from Workspace'};
    validUnits = ["", "cm", "cm/s", "pixels", "pixels/frame"];

    data = Shared.SessionData.instance();
    
    %% draw GUI
    mousePos=mousePos-[250 250];
    maskFig = uifigure('Name', 'Edit Mask', 'Position', Shared.place_window([mousePos 500 500]), ...
        'CloseRequestFcn', @onClose);


    %% Root layout
    rootGrid = uigridlayout(maskFig, [2 1], RowHeight= {'1x', 50});

    tabGroup = uitabgroup(rootGrid);

    %% bottom command buttons
    bottomGrid = uigridlayout(rootGrid, [1 3]);
    uibutton( ...
        bottomGrid, ...
        'push', ...
        'Text', 'Preview', ...
        'ButtonPushedFcn', @previewMask);
    uibutton( ...
        bottomGrid, ...
        'push', ...
        'Text', 'Generate Mask', ...
        'ButtonPushedFcn', @generateMaskAndClose);
    uibutton( ...
        bottomGrid, ...
        'push', ...
        'Text', 'Cancel', ...
        'ButtonPushedFcn', @cancelAndClose);

    %% Trace-threshold tab.
    traceTab = uitab(tabGroup, 'Title', 'Trace threshold');

    traceGrid = uigridlayout(traceTab, [5 2], Padding=[20,20,20,20]);
    traceGrid.RowHeight = {
        'fit'   % import buttons
        'fit'   % smoothing controls
        'fit'   % threshold controls
        'fit'   % status label
        '1x'    % plot preview
        };
    traceGrid.ColumnWidth = {120, '1x'};


    % Import controls
    importSourceDropDown = uidropdown( ...
        traceGrid, ...
        'Items', importSources, ...
        'Value', 'from Behavior');

    uibutton( ...
        traceGrid, ...
        'push', ...
        'Text', 'Import Trace', ...
        'ButtonPushedFcn', @importTrace);

    % Smoothing controls
    smoothCheckBox = uicheckbox( ...
        traceGrid, ...
        'Text', 'Smooth', ...
        'Value', false, ...
        'ValueChangedFcn', @smoothSettingChanged);
    
    smoothWindowField = uieditfield( ...
        traceGrid, ...
        'numeric', ...
        'Value', 1, ...
        'Limits', [0 Inf], 'LowerLimitInclusive', 'off', ...
        'Enable', 'off', ...
        'ValueChangedFcn', @traceParameterChanged, ...
        'ValueDisplayFormat','Smooth Window: %.2f s');

    % Threshold controls
    traceOperatorDropDown = uidropdown( ...
        traceGrid, ...
        'Items', {'>', '<'}, ...
        'Value', '>', ...
        'ValueChangedFcn', @traceParameterChanged);

    traceThresholdField = uieditfield( ...
        traceGrid, ...
        'numeric', ...
        'Value', 0, ...
        'ValueChangedFcn', @traceParameterChanged, ...
        'ValueDisplayFormat','Threshold: %.2f');

    % Status area
    traceStatusLabel = uilabel( ...
        traceGrid, ...
        'Text', '', ...
        'VerticalAlignment', 'top', 'WordWrap', 'on', ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 4, 'Column', [1 2]));

    % Preview plot
    tracePlotAxes = uiaxes(traceGrid);
    tracePlotAxes.Layout.Row = 5;
    tracePlotAxes.Layout.Column = [1 2];
    tracePlotAxes.XLabel.String = 'Time (s)';
    tracePlotAxes.YLabel.String = 'Trace';
    tracePlotAxes.Box = 'off';

    %% Manual-rule tab 
    manualTab = uitab( ...
        tabGroup, ...
        'Title', 'Manual rules');

    manualGrid = uigridlayout(manualTab, [3 1]);
    manualGrid.RowHeight = {
        'fit'  % rule editor
        '1x'   % table
        'fit'  % command buttons
        };

    manualGrid.ColumnWidth = {'1x'};

    % Rule editor
    editorGrid = uigridlayout(manualGrid, [2 4]);
    editorGrid.ColumnWidth = {'1x', 100, 100,100};

    enabledCheckBox = uicheckbox( ...
        editorGrid, ...
        'Text', 'Enabled', ...
        'Value', true);
    fromField = uieditfield(editorGrid, 'numeric', 'Value', 0, ...
        'LowerLimitInclusive', 'on', 'ValueDisplayFormat','From: %.2f s');
    toField = uieditfield(editorGrid, 'numeric', 'Value', 1, ...
        'LowerLimitInclusive', 'on', 'ValueDisplayFormat','To: %.2f s');
    valueDropDown = uidropdown(editorGrid, 'Items', {'Good','Bad'}, ...
        'Value', 'Good');
    
    selectedRuleLabel = uilabel(editorGrid, 'Text', 'No rule selected','WordWrap','on', ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 2, 'Column', [1 2]));
    uibutton(editorGrid,'push', 'Text', 'Add', ...
        'ButtonPushedFcn', @addRule);
    updateButton = uibutton(editorGrid, 'push', 'Text', 'Update', ...
        'Enable', 'off', 'ButtonPushedFcn', @updateRule);


    % Rule table
    ruleTable = uitable( ...
        manualGrid, ...
        'ColumnName', {'Enabled', 'From', 'To', 'Value'}, ...
        'ColumnEditable', [true false false false], ...
        'ColumnWidth', {70, 100, 100, 80}, ...
        'RowName', {}, ...
        'CellSelectionCallback', @selectRule, ...
        'CellEditCallback', @tableCellEdited);

    % Command buttons
    buttonGrid = uigridlayout(manualGrid, [2 4], ColumnWidth = {'1x', 100, 100, 100});

    moveUpButton = uibutton( ...
        buttonGrid, ...
        'push', ...
        'Text', 'Move up', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @moveRuleUp);

    moveDownButton = uibutton( ...
        buttonGrid, ...
        'push', ...
        'Text', 'Move down', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @moveRuleDown);

    duplicateButton = uibutton( ...
        buttonGrid, ...
        'push', ...
        'Text', 'Duplicate', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @duplicateRule);

    deleteButton = uibutton( ...
        buttonGrid, ...
        'push', ...
        'Text', 'Delete', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @deleteRule);

    uilabel( ...
        buttonGrid, ...
        'Text', ...
        'Applied top-to-bottom; later rules override earlier rules.', ...
        'HorizontalAlignment', 'center', 'WordWrap','on',...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 2, 'Column', [1 2]));

    uibutton( ...
        buttonGrid, ...
        'push', ...
        'Text', 'Clear selection', ...
        'ButtonPushedFcn', @clearSelection);

    uibutton( ...
        buttonGrid, ...
        'push', ...
        'Text', 'Clear all', ...
        'ButtonPushedFcn', @clearAllRules);

    % Restore a previously committed configuration, if one is usable.
    restoreSavedState();
    applyStateToUI();

    % Keep the rule table and plot synchronized with restored state.
    refreshRuleTable();
    updateTracePlot();

    %% Trace threshold functions
    function importTrace(~, ~)
        switch importSourceDropDown.Value
            case 'from Behavior'
                importTraceFromBehavior()
            case 'from Pose'
                importTraceFromPose()
            case 'from Ephys'
                importTraceFromEphys()
            case 'from File'
                readTraceFromFile()
            case 'from Workspace'
                importTraceFromWorkspace()
        end
    end

    function readTraceFromFile()
        startIn = data.defaultPath;
        if ~isempty(startIn), startIn = [startIn filesep]; end
        [fileName, folder] = uigetfile( ...
            { ...
            '*.mat',       'MAT-files (*.mat)'
            '*.csv;*.txt', 'Delimited text (*.csv, *.txt)'
            '*.*',         'All files'
            }, ...
            'Select trace file', startIn);

        if isequal(fileName, 0)
            return
        end

        filePath = fullfile(folder, fileName);
        data.rememberPath(filePath);
        [~, ~, extension] = fileparts(filePath);
    
        switch lower(extension)
            case '.mat'
                loadedData = load(filePath);
    
                [trace, time] = selectTraceFromStruct( ...
                    loadedData, ...
                    sprintf('Variables in %s', fileName));

            case {'.csv', '.txt'}
                importedData = readmatrix(filePath);

                if isempty(importedData)
                    error('DrawGUI:EmptyTraceFile', ...
                        'The selected file contains no numeric data.');
                end

                [trace, time] = interpretTraceMatrix(importedData);

            otherwise
                error('DrawGUI:UnsupportedTraceFile', ...
                    'Unsupported trace-file extension: %s', extension);
        end

        if isempty(trace)
            return
        end

        setTrace(trace, time, "File: " + string(fileName));
    end

    function importTraceFromWorkspace()
    
        workspaceInfo = evalin('base', 'whos');
    
        isNumeric = ismember( ...
            {workspaceInfo.class}, ...
            {'double','single'});
    
        workspaceInfo = workspaceInfo(isNumeric);
    
        if isempty(workspaceInfo)
            uialert( ...
                maskFig, ...
                'No numeric variables were found in the base workspace.', ...
                'Import trace');
            return
        end

        variableNames = string({workspaceInfo.name});

        [selection, confirmed] = listdlg( ...
            'PromptString', 'Select trace variable:', ...
            'SelectionMode', 'single', ...
            'ListString', cellstr(variableNames), ...
            'ListSize', [300 300]);
    
        if ~confirmed
            return
        end
    
        variableName = variableNames(selection);
        value = evalin('base', variableName);
    
        if isvector(value)
            trace = value(:);
            time = double.empty(0,1);

        elseif ismatrix(value) && size(value,2) == 2
            time  = value(:,1);
            trace = value(:,2);

        else
            error('DrawGUI:InvalidWorkspaceTrace', ...
                ['The selected variable must be a vector or an N-by-2 ' ...
                 'matrix containing [time, trace].']);
        end

        setTrace( ...
            trace, ...
            time, ...
            "Workspace: " + variableName);
    end

    % Body-part X, Y or speed of the Behavior module, one value per frame,
    % in cm and cm/s.
    function importTraceFromBehavior()
        if ~data.has('behav') || ~isfield(data.behav, 'bodypart') || ...
                isempty(data.behav.bodypart)
            uialert(maskFig, 'Import behavior data first.', 'No behavior data');
            return
        end
        partList = {data.behav.bodypart.name};
        [bodyIdx, quantity] = chooseBodypartTrace(partList);
        if isempty(bodyIdx), return; end
        bodypart = data.behav.bodypart(bodyIdx);
        switch quantity
            case 'X',     trace = bodypart.x;     units = 'cm';
            case 'Y',     trace = bodypart.y;     units = 'cm';
            case 'Speed', trace = bodypart.speed; units = 'cm/s';
        end
        setTrace(trace(:), [], ...
            "Behavior: " + string(partList{bodyIdx}) + " " + quantity, units);
    end

    % Body-part X, Y (pixels) or speed (pixels/frame, shown in cm/s) from
    % the Pose module, or from the Behavior module's raw pose.
    function importTraceFromPose()
        if data.has('pose')
            partList = data.pose.hd.bodypart.Items;
        elseif data.has('behav')
            partList = {data.behav.bodypart.name};
        else
            uialert(maskFig, 'Import behavior or pose data first.', 'No pose data'); return;
        end
        [bodyIdx, quantity] = chooseBodypartTrace(partList);
        if isempty(bodyIdx), return; end
        bodyName = partList{bodyIdx};
        if data.has('pose')
            x = data.pose.table.([bodyName '_x']);
            y = data.pose.table.([bodyName '_y']);
        else
            x = data.behav.bodypart(bodyIdx).rawX;
            y = data.behav.bodypart(bodyIdx).rawY;
        end
        switch quantity
            case 'X',     trace = x; units = 'pixels';
            case 'Y',     trace = y; units = 'pixels';
            case 'Speed', trace = Behav.smooth_speed(x,y,1); units = 'pixels/frame';
        end
        setTrace(trace(:), [], ...
            "Pose: " + string(bodyName) + " " + quantity, units);
    end

    % Asks for a body part, then X, Y or Speed; empty bodyIdx if cancelled.
    function [bodyIdx, quantity] = chooseBodypartTrace(partList)
        quantity = '';
        [bodyIdx, tf] = listdlg('PromptString','Select bodypart:', ...
            'ListString',partList, 'SelectionMode','single');
        drawnow; figure(maskFig);
        if ~tf, bodyIdx = []; return; end
        quantities = {'X', 'Y', 'Speed'};
        [k, tf] = listdlg('PromptString', ...
            sprintf('Select trace of %s:', partList{bodyIdx}), ...
            'ListString', quantities, 'SelectionMode', 'single', ...
            'ListSize', [200 100]);
        drawnow; figure(maskFig);
        if ~tf, bodyIdx = []; return; end
        quantity = quantities{k};
    end

    % An Ephys digital channel as a 0/1 step trace on the Ephys clock: the
    % level changes at each rising or falling edge and holds until the next.
    % Outside the recording the level is unknown (NaN, masked out).
    function importTraceFromEphys()
        if isempty(data.ephys) || ~isfield(data.ephys, 'digital') || ...
                isempty(data.ephys.digital)
            uialert(maskFig, 'Open an ephys recording with digital channels first.', ...
                'No digital channels');
            return
        end
        digital = data.ephys.digital;
        labels = arrayfun(@Ephys.ttl_stats, digital, 'UniformOutput', false);
        [k, tf] = listdlg('PromptString', 'Select digital channel:', ...
            'ListString', labels, 'SelectionMode', 'single', ...
            'ListSize', [300 200]);
        drawnow; figure(maskFig);
        if ~tf, return; end
        channel = digital(k);

        edgeTime  = [channel.rise(:); channel.fall(:)];
        edgeLevel = [ones(numel(channel.rise), 1); zeros(numel(channel.fall), 1)];
        [edgeTime, order] = sort(edgeTime);
        edgeLevel = edgeLevel(order);
        % Level before the first edge: the opposite of that edge; low when
        % the channel never changes.
        if isempty(edgeLevel)
            startLevel = 0;
        else
            startLevel = 1 - edgeLevel(1);
        end

        [t0, t1] = ephysSpan();
        if isnan(t0)
            % No recording times: start just before the first edge.
            if isempty(edgeTime), t0 = 0; else, t0 = edgeTime(1) - 1; end
        end
        if ~isempty(edgeTime), t0 = min(t0, edgeTime(1)); end
        time  = [t0; edgeTime];
        level = [startLevel; edgeLevel];
        % After the recording the level is unknown.
        if ~isnan(t1) && t1 > time(end)
            time(end+1)  = t1;
            level(end+1) = NaN;
        end
        % Edges at the same time: the last one wins.
        [time, last] = unique(time, 'last');
        level = level(last);

        if ~isfield(data.ephys, 'sync') || isempty(data.ephys.sync)
            uialert(maskFig, ['Ephys is not synchronized: frame times are ' ...
                'frame / frame rate and may not match the ephys clock.'], ...
                'Not synchronized', 'Icon', 'warning');
        end
        setTrace(level, time, "Ephys: " + string(channel.name), '', 'previous');
    end

    % First and last time of the ephys recording; NaN if unknown.
    function [t0, t1] = ephysSpan()
        t0 = NaN; t1 = NaN;
        t = [];
        if isfield(data.ephys, 'raw') && ~isempty(data.ephys.raw) && ...
                isfield(data.ephys.raw, 't')
            t = data.ephys.raw(1).t;
        elseif isfield(data.ephys, 'processed') && ~isempty(data.ephys.processed)
            t = data.ephys.processed(1).t;
        end
        if ~isempty(t)
            t0 = t(1); t1 = t(end);
        end
    end

    function smoothSettingChanged(~, ~)
        state.SmoothEnabled = smoothCheckBox.Value;
        smoothWindowField.Enable = onOff(smoothCheckBox.Value);
        traceParameterChanged();
    end

    function traceParameterChanged(~, ~)
        captureControlState();
        updateTraceStatus();
        updateTracePlot();
    end

    function setTrace(trace, time, source, units, interpMethod)
        if nargin < 4, units = ''; end
        if nargin < 5, interpMethod = 'linear'; end

        trace = double(trace(:));
        time  = double(time(:));

        if isempty(trace)
            error('DrawGUI:EmptyTrace', ...
                'Trace data cannot be empty.');
        end

        if any(isinf(trace))
            error('DrawGUI:InvalidTrace', ...
                'Trace data contains Inf values.');
        end

        if ~isempty(time)

            if numel(time) ~= numel(trace)
                error('DrawGUI:TraceTimeSizeMismatch', ...
                    'Time and trace must contain the same number of elements.');
            end

            if any(~isfinite(time)) || any(diff(time) <= 0)
                error('DrawGUI:InvalidTraceTime', ...
                    'The trace time vector must be finite and strictly increasing.');
            end
        end

        state.Trace       = trace;
        state.TraceTime   = time;
        state.TraceSource = source;
        state.TraceUnits  = units;
        state.TraceInterp = interpMethod;

        updateTraceStatus();
        updateTracePlot();
        syncPublicState();
    end

    function [trace, time] = getProcessedTrace()

        trace = state.Trace;
        time  = state.TraceTime;
        if strcmp(state.TraceUnits, 'pixels/frame')
            trace = trace * data.getFrameRate()/data.behav.hd.resolution.Value;
        end

        if isempty(trace)
            return
        end

        if ~isempty(time)
            targetTime = data.behav.t(:);
            if strcmp(state.TraceInterp, 'previous')
                % step data: the last value at or before each frame time
                k = discretize(targetTime, [time; Inf]);
                stepped = NaN(size(targetTime));
                stepped(~isnan(k)) = trace(k(~isnan(k)));
                trace = stepped;
            else
                if numel(time) < 2
                    error('DrawGUI:TraceTime', 'Timestamped trace needs at least two samples.');
                end
                trace = interp1(time, trace, targetTime, 'linear', NaN);
            end
            time = targetTime;
        else
            time = data.behav.t(:);
            if numel(trace) ~= numel(time)
                error('DrawGUI:TraceSizeMismatch', 'Untimed trace must match the behavior sample count.');
            end
        end
        if state.SmoothEnabled
            window = getSmoothWindowSamples();

            missing = ~isfinite(trace);
            trace = movmean(trace, window, 'omitnan', 'Endpoints', 'shrink');
            trace(missing) = NaN;
        end
    end

    % Units of the processed trace, '' if none.
    function units = processedUnits()
        units = state.TraceUnits;
        if strcmp(units, 'pixels/frame'), units = 'cm/s'; end
    end

    function mask = generateTraceMask()
        if isempty(state.Trace)
            traceSize = getTraceSize();
            nSamples = prod(traceSize);
            mask = true(nSamples, 1);
            return
        end

        [trace, ~] = getProcessedTrace();
        threshold = state.TraceThreshold;
        switch state.TraceOperator
            case '>'
                mask = trace > threshold;
            case '<'
                mask = trace < threshold;
            otherwise
                error('DrawGUI:InvalidTraceOperator', ...
                    'Unsupported trace operator.');
        end
    end

    function updateTraceStatus()

        if isempty(state.Trace)
            traceStatusLabel.Text = 'No trace data loaded.';
            return
        end

        units = '';
        if ~isempty(state.TraceUnits), units = [' ' state.TraceUnits]; end
        text = sprintf( ...
            ['Samples: %d\n' ...
             'Range: %.6g to %.6g%s\n' ...
             'Rule: trace %s %.6g'], ...
            numel(state.Trace), ...
            min(state.Trace), ...
            max(state.Trace), ...
            units, ...
            state.TraceOperator, ...
            state.TraceThreshold);
        if ~isempty(processedUnits())
            text = sprintf('%s %s', text, processedUnits());
        end
    
        if state.SmoothEnabled
            text = sprintf( ...
                '%s\nSmoothing: moving mean, %.3g s', ...
                text, ...
                state.SmoothWindow);
        else
            text = sprintf('%s\nSmoothing: off', text);
        end
    
        traceStatusLabel.Text = text;
    end

    function n = getSmoothWindowSamples()
        windowSeconds = state.SmoothWindow;
        if ~isfinite(windowSeconds) || windowSeconds <= 0
            error('DrawGUI:InvalidSmoothWindow', ...
                'The smoothing window must be finite and greater than zero.');
        end

        fs = getFrameRate();
        n = max(1, round(windowSeconds * fs));
    end

    function updateTracePlot()
        if isempty(state.Trace) || ~isvalid(tracePlotAxes)
            cla(tracePlotAxes);
            title(tracePlotAxes, 'No trace data loaded');
            tracePlotAxes.YLabel.String = 'Trace';
            return
        end

        [trace, x] = getProcessedTrace();
        tracePlotAxes.XLabel.String = 'Time (s)';
        tracePlotAxes.YLabel.String = traceLabel('Trace');

        good = generateTraceMask();
        goodTrace = trace;
        badTrace = trace;
        bad = ~good;
        bad = bad | circshift(bad, 1) | circshift(bad, -1);
        goodTrace(~good) = NaN;
        badTrace(~bad) = NaN;

        cla(tracePlotAxes);
        hold(tracePlotAxes, 'on');
        style = Shared.styles();
        plot(tracePlotAxes, x, badTrace, ...
            'Color', style.unmaskedColor, 'LineWidth', 1);
        plot(tracePlotAxes, x, goodTrace, ...
            'Color', style.maskedColor, 'LineWidth', 1.25);
        yline(tracePlotAxes, ...
            state.TraceThreshold, '--', 'Threshold', ...
            'Color', style.maskPreviewThresh, 'LineWidth', 1);
        hold(tracePlotAxes, 'off');
        grid(tracePlotAxes, 'off');
        title(tracePlotAxes, state.TraceSource, 'Interpreter', 'none');
    end

    % name with the processed units, e.g. 'Trace (cm/s)'
    function label = traceLabel(name)
        label = name;
        if ~isempty(processedUnits())
            label = sprintf('%s (%s)', name, processedUnits());
        end
    end

    function [trace, time] = selectTraceFromStruct(data, dialogTitle)
    
        names = string(fieldnames(data));
    
        keep = false(size(names));
    
        for index = 1:numel(names)
            value = data.(names(index));
    
            keep(index) = ...
                isnumeric(value) && ...
                isreal(value) && ...
                (isvector(value) || ...
                 (ismatrix(value) && size(value,2) == 2));
        end
    
        names = names(keep);
    
        if isempty(names)
            error('DrawGUI:NoTraceVariables', ...
                ['No numeric vector or N-by-2 numeric matrix was found ' ...
                 'in the selected MAT-file.']);
        end

        [selection, confirmed] = listdlg( ...
            'PromptString', 'Select trace variable:', ...
            'SelectionMode', 'single', ...
            'ListString', cellstr(names), ...
            'ListSize', [300 300], ...
            'Name', dialogTitle);

        if ~confirmed
            trace = double.empty(0,1);
            time  = double.empty(0,1);
            return
        end

        value = data.(names(selection));

        if isvector(value)
            trace = value(:);
            time  = double.empty(0,1);
        else
            time  = value(:,1);
            trace = value(:,2);
        end
    end
    function [trace, time] = interpretTraceMatrix(value)

        value = double(value);

        % Remove completely empty rows introduced by headers or trailing lines.
        value = value(~all(isnan(value),2), :);

        if isvector(value)
            trace = value(:);
            time  = double.empty(0,1);

        elseif size(value,2) == 1
            trace = value(:,1);
            time  = double.empty(0,1);

        elseif size(value,2) == 2
            time  = value(:,1);
            trace = value(:,2);

        else
            error('DrawGUI:AmbiguousTraceFile', ...
                ['The file must contain either one trace column or two ' ...
                 'columns arranged as [time, trace].']);
        end
    end

    %% Manual rules functions

    function addRule(~, ~)

        [fromTime, toTime, value, enabled] = readEditor();

        newRule = table( ...
            state.NextRuleID, ...
            enabled, ...
            fromTime, ...
            toTime, ...
            value, ...
            'VariableNames', state.Rules.Properties.VariableNames);

        state.NextRuleID = state.NextRuleID + 1;
        state.Rules = [state.Rules; newRule];

        state.SelectedRow = height(state.Rules);

        refreshRuleTable();
        loadSelectedRuleIntoEditor();
    end

    function updateRule(~, ~)
        row = state.SelectedRow;

        if ~isValidSelectedRow(row)
            return
        end

        [fromTime, toTime, value, enabled] = readEditor();

        state.Rules.Enabled(row)  = enabled;
        state.Rules.FromTime(row) = fromTime;
        state.Rules.ToTime(row)   = toTime;
        state.Rules.Value(row)    = value;

        refreshRuleTable();
        loadSelectedRuleIntoEditor();
    end

    function selectRule(~, event)

        if isempty(event.Indices)
            clearSelection();
            return
        end

        row = event.Indices(1,1);

        if row < 1 || row > height(state.Rules)
            clearSelection();
            return
        end

        state.SelectedRow = row;

        loadSelectedRuleIntoEditor();
        updateButtonStates();
        syncPublicState();
    end

    function tableCellEdited(~, event)

        row = event.Indices(1);
        column = event.Indices(2);

        if row < 1 || row > height(state.Rules)
            refreshRuleTable();
            return
        end

        % Only the Enabled column is currently directly editable.
        if column == 1
            state.Rules.Enabled(row) = logical(event.NewData);
        end

        state.SelectedRow = row;

        refreshRuleTable();
        loadSelectedRuleIntoEditor();
    end

    function moveRuleUp(~, ~)

        row = state.SelectedRow;

        if ~isValidSelectedRow(row) || row == 1
            return
        end

        state.Rules([row-1 row], :) = state.Rules([row row-1], :);
        state.SelectedRow = row - 1;

        refreshRuleTable();
        loadSelectedRuleIntoEditor();
    end

    function moveRuleDown(~, ~)

        row = state.SelectedRow;
        nRules = height(state.Rules);

        if ~isValidSelectedRow(row) || row == nRules
            return
        end

        state.Rules([row row+1], :) = state.Rules([row+1 row], :);
        state.SelectedRow = row + 1;

        refreshRuleTable();
        loadSelectedRuleIntoEditor();
    end

    function duplicateRule(~, ~)

        row = state.SelectedRow;

        if ~isValidSelectedRow(row)
            return
        end

        duplicatedRule = state.Rules(row,:);
        duplicatedRule.ID = state.NextRuleID;

        state.NextRuleID = state.NextRuleID + 1;

        if row == height(state.Rules)
            state.Rules = [state.Rules; duplicatedRule];
        else
            state.Rules = [
                state.Rules(1:row,:)
                duplicatedRule
                state.Rules(row+1:end,:)
                ];
        end

        state.SelectedRow = row + 1;

        refreshRuleTable();
        loadSelectedRuleIntoEditor();
    end

    function deleteRule(~, ~)

        row = state.SelectedRow;

        if ~isValidSelectedRow(row)
            return
        end

        state.Rules(row,:) = [];

        if isempty(state.Rules)
            state.SelectedRow = NaN;
        else
            state.SelectedRow = min(row, height(state.Rules));
        end

        refreshRuleTable();

        if isValidSelectedRow(state.SelectedRow)
            loadSelectedRuleIntoEditor();
        end
    end

    function clearSelection(~, ~)

        state.SelectedRow = NaN;

        selectedRuleLabel.Text = 'No rule selected';

        refreshRuleTable();
    end

    function clearAllRules(~, ~)

        if isempty(state.Rules)
            return
        end

        selection = uiconfirm( ...
            maskFig, ...
            'Delete all manual mask rules?', ...
            'Clear rules', ...
            'Options', {'Delete all','Cancel'}, ...
            'DefaultOption', 'Cancel', ...
            'CancelOption', 'Cancel');

        if ~strcmp(selection, 'Delete all')
            return
        end

        state.Rules(:,:) = [];
        state.SelectedRow = NaN;

        refreshRuleTable();
    end

    function [fromTime, toTime, value, enabled] = readEditor()

        fromTime = fromField.Value;
        toTime   = toField.Value;
        enabled  = enabledCheckBox.Value;
        value    = strcmp(valueDropDown.Value, 'Good');

        if ~isfinite(fromTime) || ~isfinite(toTime)
            error('DrawGUI:InvalidTime', ...
                'FromTime and ToTime must be finite.');
        end

        if fromTime >= toTime
            error('DrawGUI:InvalidInterval', ...
                'FromTime must be less than ToTime.');
        end
    end

    function loadSelectedRuleIntoEditor()

        row = state.SelectedRow;

        if ~isValidSelectedRow(row)
            selectedRuleLabel.Text = 'No rule selected';
            updateButtonStates();
            return
        end

        rule = state.Rules(row,:);

        fromField.Value       = rule.FromTime;
        toField.Value         = rule.ToTime;
        enabledCheckBox.Value = rule.Enabled;

        if rule.Value
            valueDropDown.Value = 'Good';
        else
            valueDropDown.Value = 'Bad';
        end

        selectedRuleLabel.Text = sprintf( ...
            'Selected rule %d of %d  [ID %d]', ...
            row, height(state.Rules), rule.ID);

        updateButtonStates();
        syncPublicState();
    end

    function refreshRuleTable()

        nRules = height(state.Rules);

        if nRules == 0
            ruleTable.Data = table( ...
                logical.empty(0,1), ...
                double.empty(0,1), ...
                double.empty(0,1), ...
                strings(0,1), ...
                'VariableNames', ...
                {'Enabled','From','To','Value'});
        else
            valueText = repmat("Bad", nRules, 1);
            valueText(state.Rules.Value) = "Good";

            ruleTable.Data = table( ...
                state.Rules.Enabled, ...
                state.Rules.FromTime, ...
                state.Rules.ToTime, ...
                valueText, ...
                'VariableNames', ...
                {'Enabled','From','To','Value'});
        end

        if ~isValidSelectedRow(state.SelectedRow)
            state.SelectedRow = NaN;
            selectedRuleLabel.Text = 'No rule selected';
        end

        updateButtonStates();
        syncPublicState();
    end

    function updateButtonStates()

        row = state.SelectedRow;
        selected = isValidSelectedRow(row);
        nRules = height(state.Rules);

        updateButton.Enable    = onOff(selected);
        duplicateButton.Enable = onOff(selected);
        deleteButton.Enable    = onOff(selected);

        moveUpButton.Enable = onOff(selected && row > 1);
        moveDownButton.Enable = onOff(selected && row < nRules);
    end

    function rules = getRules()
        rules = state.Rules;
    end

    function setRules(rules)

        validateRulesTable(rules);

        rules = rules(:, ...
            {'ID','Enabled','FromTime','ToTime','Value'});

        rules.ID       = uint64(rules.ID);
        rules.Enabled  = logical(rules.Enabled);
        rules.FromTime = double(rules.FromTime);
        rules.ToTime   = double(rules.ToTime);
        rules.Value    = logical(rules.Value);

        if any(~isfinite(rules.FromTime)) || ...
           any(~isfinite(rules.ToTime))
            error('DrawGUI:InvalidRules', ...
                'Rule times must be finite.');
        end

        if any(rules.FromTime >= rules.ToTime)
            error('DrawGUI:InvalidRules', ...
                'Every rule must satisfy FromTime < ToTime.');
        end

        if numel(unique(rules.ID)) ~= height(rules)
            error('DrawGUI:DuplicateRuleID', ...
                'Rule IDs must be unique.');
        end

        state.Rules = rules;
        state.SelectedRow = NaN;

        if isempty(rules)
            state.NextRuleID = uint64(1);
        else
            state.NextRuleID = max(rules.ID) + 1;
        end

        refreshRuleTable();
    end

    function mask = generateManualMask(time, defaultValue)
    %GENERATEMANUALMASK Apply enabled manual rules to a time vector.
    %
    % Intervals use:
    %   FromTime <= time < ToTime
    %
    % Rules are evaluated in table order. Later rows override earlier rows.

        if isscalar(defaultValue)
            mask = repmat(logical(defaultValue), size(time));
        else
            if numel(defaultValue) ~= numel(time)
                error('DrawGUI:MaskTimeSizeMismatch', ...
                    'The initial mask and time vector must have equal lengths.');
            end
            mask = reshape(logical(defaultValue), size(time));
        end

        for ruleIndex = 1:height(state.Rules)

            if ~state.Rules.Enabled(ruleIndex)
                continue
            end

            index = ...
                time >= state.Rules.FromTime(ruleIndex) & ...
                time <  state.Rules.ToTime(ruleIndex);

            mask(index) = state.Rules.Value(ruleIndex);
        end
    end

    function tf = isValidSelectedRow(row)

        tf = ...
            isscalar(row) && ...
            isfinite(row) && ...
            row == fix(row) && ...
            row >= 1 && ...
            row <= height(state.Rules);
    end

    function syncPublicState()
        captureControlState();
        data.behav.maskParam = state;
    end

    function captureControlState()
        state.SmoothEnabled = logical(smoothCheckBox.Value);
        state.SmoothWindow = smoothWindowField.Value;
        state.TraceOperator = traceOperatorDropDown.Value;
        state.TraceThreshold = traceThresholdField.Value;
        state.ImportSource = importSourceDropDown.Value;
    end

    % Settings saved before the speed -> trace rename used Speed* fields.
    function saved = renameLegacyFields(saved)
        legacy = {'Speed','Trace'; 'SpeedTime','TraceTime'; ...
            'SpeedSource','TraceSource'; 'SpeedUnits','TraceUnits'; ...
            'SpeedOperator','TraceOperator'; 'SpeedThreshold','TraceThreshold'};
        for k = 1:size(legacy, 1)
            if isfield(saved, legacy{k,1}) && ~isfield(saved, legacy{k,2})
                saved.(legacy{k,2}) = saved.(legacy{k,1});
            end
        end
    end

    function restoreSavedState()
        if ~isfield(data.behav, 'maskParam') || ...
                ~isstruct(data.behav.maskParam) || ...
                ~isscalar(data.behav.maskParam)
            return
        end

        saved = renameLegacyFields(data.behav.maskParam);
        candidate = defaultState;

        try
            if ~isfield(saved, 'Rules')
                return
            end

            validateRulesTable(saved.Rules);
            rules = saved.Rules(:, ...
                {'ID','Enabled','FromTime','ToTime','Value'});
            rules.ID = uint64(rules.ID);
            rules.Enabled = logical(rules.Enabled);
            rules.FromTime = double(rules.FromTime);
            rules.ToTime = double(rules.ToTime);
            rules.Value = logical(rules.Value);

            if any(~isfinite(rules.FromTime)) || ...
                    any(~isfinite(rules.ToTime)) || ...
                    any(rules.FromTime >= rules.ToTime) || ...
                    numel(unique(rules.ID)) ~= height(rules)
                return
            end
            candidate.Rules = rules;

            if isfield(saved, 'Trace') && ~isempty(saved.Trace)
                trace = double(saved.Trace(:));
                if any(isinf(trace))
                    return
                end
                candidate.Trace = trace;
            end

            if isfield(saved, 'TraceTime') && ~isempty(saved.TraceTime)
                traceTime = double(saved.TraceTime(:));
                if numel(traceTime) ~= numel(candidate.Trace) || ...
                        any(~isfinite(traceTime)) || any(diff(traceTime) <= 0)
                    return
                end
                candidate.TraceTime = traceTime;
            end

            if isfield(saved, 'TraceUnits') && ...
                    (ischar(saved.TraceUnits) || isstring(saved.TraceUnits)) && ...
                    ismember(string(saved.TraceUnits), validUnits)
                candidate.TraceUnits = char(saved.TraceUnits);
            end

            if isfield(saved, 'TraceInterp') && ...
                    (ischar(saved.TraceInterp) || isstring(saved.TraceInterp)) && ...
                    any(strcmp(saved.TraceInterp, {'linear','previous'}))
                candidate.TraceInterp = char(saved.TraceInterp);
            end

            if isfield(saved, 'TraceSource') && ...
                    (ischar(saved.TraceSource) || ...
                    (isstring(saved.TraceSource) && isscalar(saved.TraceSource)))
                candidate.TraceSource = string(saved.TraceSource);
            end

            if isfield(saved, 'SmoothEnabled') && ...
                    (islogical(saved.SmoothEnabled) || ...
                    isnumeric(saved.SmoothEnabled)) && ...
                    isscalar(saved.SmoothEnabled)
                candidate.SmoothEnabled = logical(saved.SmoothEnabled);
            elseif isfield(saved, 'SmoothWindow') && ...
                    isnumeric(saved.SmoothWindow) && ...
                    isscalar(saved.SmoothWindow) && saved.SmoothWindow == 0
                % Compatibility with the earlier zero-means-disabled state.
                candidate.SmoothEnabled = false;
            end

            if isfield(saved, 'SmoothWindow') && ...
                    isnumeric(saved.SmoothWindow) && ...
                    isscalar(saved.SmoothWindow) && ...
                    isfinite(saved.SmoothWindow) && saved.SmoothWindow > 0
                candidate.SmoothWindow = double(saved.SmoothWindow);
            end

            if isfield(saved, 'TraceOperator') && ...
                    (ischar(saved.TraceOperator) || ...
                    (isstring(saved.TraceOperator) && isscalar(saved.TraceOperator))) && ...
                    any(strcmp(saved.TraceOperator, {'>','<'}))
                candidate.TraceOperator = char(saved.TraceOperator);
            end

            if isfield(saved, 'TraceThreshold') && ...
                    isnumeric(saved.TraceThreshold) && ...
                    isscalar(saved.TraceThreshold) && ...
                    isfinite(saved.TraceThreshold)
                candidate.TraceThreshold = double(saved.TraceThreshold);
            end

            if isfield(saved, 'ImportSource') && ...
                    (ischar(saved.ImportSource) || ...
                    (isstring(saved.ImportSource) && isscalar(saved.ImportSource))) && ...
                    any(strcmp(saved.ImportSource, importSources))
                candidate.ImportSource = char(saved.ImportSource);
            end

            candidate.SelectedRow = NaN;
            if isempty(candidate.Rules)
                candidate.NextRuleID = uint64(1);
            else
                candidate.NextRuleID = max(candidate.Rules.ID) + 1;
            end

            state = candidate;
        catch
            % Ignore malformed or incompatible saved state and use defaults.
            state = defaultState;
        end
    end

    function applyStateToUI()
        smoothCheckBox.Value = state.SmoothEnabled;
        smoothWindowField.Value = state.SmoothWindow;
        smoothWindowField.Enable = onOff(state.SmoothEnabled);
        traceOperatorDropDown.Value = state.TraceOperator;
        traceThresholdField.Value = state.TraceThreshold;
        importSourceDropDown.Value = state.ImportSource;
    end

    function fs = getFrameRate()
        fs = double(data.getFrameRate());
        if ~isscalar(fs) || ~isfinite(fs) || fs <= 0
            error('DrawGUI:InvalidFrameRate', ...
                'data.getFrameRate() must return a finite positive scalar.');
        end
    end

    function traceSize = getTraceSize()
        if ~isfield(data.behav, 't') || isempty(data.behav.t)
            error('DrawGUI:MissingBehavTrace', 'Import behavior data before editing a mask.');
        end
        traceSize = size(data.behav.t);
    end

    %% Bottom command functions

    function previewMask(~, ~)
        data.behav.maskTemp = buildCombinedMask();
        % trace and threshold for the Behavior viewer; colored by the trace
        % rule only, without the manual rules
        if isempty(state.Trace)
            removeTracePreview();
        else
            [trace, time] = getProcessedTrace();
            data.behav.maskTempTrace = struct('t', time, 'trace', trace, ...
                'good', generateTraceMask(), 'threshold', state.TraceThreshold, ...
                'label', traceLabel('Mask trace'));
        end
        notify(data, 'MaskPreviewChanged');
    end

    function removeTracePreview()
        if isfield(data.behav, 'maskTempTrace')
            data.behav = rmfield(data.behav, 'maskTempTrace');
        end
    end

    function generateMaskAndClose(~, ~)
        data.behav.mask = buildCombinedMask();
        if isfield(data.behav, 'maskTemp'), data.behav = rmfield(data.behav, 'maskTemp'); end
        removeTracePreview();
        syncPublicState();
        notify(data, 'MaskChanged');
        close(maskFig);
    end

    function cancelAndClose(~, ~)
        close(maskFig);
    end

    function mask = buildCombinedMask()
        captureControlState();

        % The body-part trace defines the authoritative mask size and sample grid.
        traceSize = getTraceSize();
        nSamples = prod(traceSize);
        fs = getFrameRate();
        time = data.behav.t(:);

        % No trace means no automatic exclusion: start with an all-good mask.
        if isempty(state.Trace)
            mask = true(nSamples, 1);
        else
            mask = generateTraceMask();
            if numel(mask) ~= nSamples
                error('DrawGUI:TraceSizeMismatch', ...
                    ['Imported trace has %d samples, but ' ...
                     'behavior time vector has %d samples.'], ...
                    numel(mask), nSamples);
            end
            mask = logical(mask(:));
        end

        mask = generateManualMask(time, mask);
        mask = reshape(logical(mask), traceSize);
    end

    function onClose(src, ~)
        if isfield(data.behav, 'maskTemp')
            data.behav = rmfield(data.behav, 'maskTemp');
        end
        removeTracePreview();
        notify(data, 'MaskPreviewChanged');
        delete(src);
        notify(data, 'WindowsChanged');
    end
end


function validateRulesTable(rules)

    if ~istable(rules)
        error('DrawGUI:InvalidRulesType', ...
            'Rules must be provided as a table.');
    end

    requiredVariables = {
        'ID'
        'Enabled'
        'FromTime'
        'ToTime'
        'Value'
        };

    missingVariables = setdiff( ...
        requiredVariables, ...
        rules.Properties.VariableNames);

    if ~isempty(missingVariables)
        error('DrawGUI:MissingRuleVariables', ...
            'Rules table is missing variables: %s', ...
            strjoin(missingVariables, ', '));
    end
end


function value = onOff(tf)

    if tf
        value = 'on';
    else
        value = 'off';
    end
end

