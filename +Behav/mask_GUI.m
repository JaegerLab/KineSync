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

    state.Speed = double.empty(0,1);
    state.SpeedTime = double.empty(0,1);
    state.SpeedSource = "";
    state.SpeedUnits = 'cm/s';
    state.SmoothEnabled = false;
    state.SmoothWindow = 1;
    state.SpeedOperator = '>';
    state.SpeedThreshold = 0;
    state.ImportSource = 'from Pose';

    defaultState = state;

    speedGoodLine = gobjects(0);
    speedBadLine = gobjects(0);
    speedThresholdLine = gobjects(0);

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

    %% Speed-threshold tab.
    speedTab = uitab(tabGroup, 'Title', 'Speed threshold');

    speedGrid = uigridlayout(speedTab, [5 2], Padding=[20,20,20,20]);
    speedGrid.RowHeight = {
        'fit'   % import buttons
        'fit'   % smoothing controls
        'fit'   % threshold controls
        'fit'   % status label
        '1x'    % plot preview
        };
    speedGrid.ColumnWidth = {120, '1x'};

    
    % Import controls
    importSourceDropDown = uidropdown( ...
        speedGrid, ...
        'Items', {'from Pose', 'from File', 'from Workspace'}, ...
        'Value', 'from Pose');
    
    uibutton( ...
        speedGrid, ...
        'push', ...
        'Text', 'Import Speed', ...
        'ButtonPushedFcn', @importSpeed);

    % Smoothing controls
    smoothCheckBox = uicheckbox( ...
        speedGrid, ...
        'Text', 'Smooth', ...
        'Value', false, ...
        'ValueChangedFcn', @smoothSettingChanged);
    
    smoothWindowField = uieditfield( ...
        speedGrid, ...
        'numeric', ...
        'Value', 1, ...
        'Limits', [0 Inf], 'LowerLimitInclusive', 'off', ...
        'Enable', 'off', ...
        'ValueChangedFcn', @speedParameterChanged, ...
        'ValueDisplayFormat','Smooth Window: %.2f s');
    
    % Threshold controls
    speedOperatorDropDown = uidropdown( ...
        speedGrid, ...
        'Items', {'>', '<'}, ...
        'Value', '>', ...
        'ValueChangedFcn', @speedParameterChanged);
    
    speedThresholdField = uieditfield( ...
        speedGrid, ...
        'numeric', ...
        'Value', 0, ...
        'ValueChangedFcn', @speedParameterChanged, ...
        'ValueDisplayFormat','Threshold: %.2f');
    
    % Status area
    speedStatusLabel = uilabel( ...
        speedGrid, ...
        'Text', '', ...
        'VerticalAlignment', 'top', 'WordWrap', 'on', ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 4, 'Column', [1 2]));

    % Preview plot
    speedPlotAxes = uiaxes(speedGrid);
    speedPlotAxes.Layout.Row = 5;
    speedPlotAxes.Layout.Column = [1 2];
    speedPlotAxes.XLabel.String = 'Time (s)';
    speedPlotAxes.YLabel.String = 'Speed';
    speedPlotAxes.Box = 'off';

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
    updateSpeedPlot();

    %% Speed threshold functions
    function importSpeed(~, ~)
        switch importSourceDropDown.Value
            case 'from Pose'
                importSpeedFromPose()
            case 'from File'
                readSpeedFromFile()
            case 'from Workspace'
                importSpeedFromWorkspace()
        end
    end

    function readSpeedFromFile()
        startIn = data.defaultPath;
        if ~isempty(startIn), startIn = [startIn filesep]; end
        [fileName, folder] = uigetfile( ...
            { ...
            '*.mat',       'MAT-files (*.mat)'
            '*.csv;*.txt', 'Delimited text (*.csv, *.txt)'
            '*.*',         'All files'
            }, ...
            'Select speed file', startIn);

        if isequal(fileName, 0)
            return
        end

        filePath = fullfile(folder, fileName);
        data.rememberPath(filePath);
        [~, ~, extension] = fileparts(filePath);
    
        switch lower(extension)
            case '.mat'
                loadedData = load(filePath);
    
                [speed, time] = selectSpeedFromStruct( ...
                    loadedData, ...
                    sprintf('Variables in %s', fileName));
    
            case {'.csv', '.txt'}
                importedData = readmatrix(filePath);
    
                if isempty(importedData)
                    error('DrawGUI:EmptySpeedFile', ...
                        'The selected file contains no numeric data.');
                end
    
                [speed, time] = interpretSpeedMatrix(importedData);
    
            otherwise
                error('DrawGUI:UnsupportedSpeedFile', ...
                    'Unsupported speed-file extension: %s', extension);
        end
    
        if isempty(speed)
            return
        end

        setSpeed(speed, time, "File: " + string(fileName));
    end

    function importSpeedFromWorkspace()
    
        workspaceInfo = evalin('base', 'whos');
    
        isNumeric = ismember( ...
            {workspaceInfo.class}, ...
            {'double','single'});
    
        workspaceInfo = workspaceInfo(isNumeric);
    
        if isempty(workspaceInfo)
            uialert( ...
                maskFig, ...
                'No numeric variables were found in the base workspace.', ...
                'Import speed');
            return
        end
    
        variableNames = string({workspaceInfo.name});
    
        [selection, confirmed] = listdlg( ...
            'PromptString', 'Select speed variable:', ...
            'SelectionMode', 'single', ...
            'ListString', cellstr(variableNames), ...
            'ListSize', [300 300]);
    
        if ~confirmed
            return
        end
    
        variableName = variableNames(selection);
        value = evalin('base', variableName);
    
        if isvector(value)
            speed = value(:);
            time = double.empty(0,1);
    
        elseif ismatrix(value) && size(value,2) == 2
            time  = value(:,1);
            speed = value(:,2);
    
        else
            error('DrawGUI:InvalidWorkspaceSpeed', ...
                ['The selected variable must be a vector or an N-by-2 ' ...
                 'matrix containing [time, speed].']);
        end
    
        setSpeed( ...
            speed, ...
            time, ...
            "Workspace: " + variableName);
    end

    function importSpeedFromPose(~, ~)
        if data.has('pose')
            partList = data.pose.hd.bodypart.Items;
        elseif data.has('behav')
            partList = {data.behav.paw.name};
        else
            uialert(maskFig, 'Import behavior or pose data first.', 'No pose data'); return;
        end
        [bodyIdx, tf] = listdlg('PromptString','Select bodypart:', ...
            'ListString',partList, 'SelectionMode','single');
        drawnow; figure(maskFig);
        if ~tf, return; end
        bodyName = partList{bodyIdx};
        if data.has('pose')
            x = data.pose.table.([bodyName '_x']);
            y = data.pose.table.([bodyName '_y']);
        else
            x = data.behav.paw(bodyIdx).rawX;
            y = data.behav.paw(bodyIdx).rawY;
        end
        speed = Behav.smooth_speed(x,y,1);
        setSpeed(speed(:), [], "Pose: " + string(bodyName), 'pixels/frame');
    end

    function smoothSettingChanged(~, ~)
        state.SmoothEnabled = smoothCheckBox.Value;
        smoothWindowField.Enable = onOff(smoothCheckBox.Value);
        speedParameterChanged();
    end

    function speedParameterChanged(~, ~)
        captureControlState();
        updateSpeedStatus();
        updateSpeedPlot();
    end

    function setSpeed(speed, time, source, units)
        if nargin<4, units = 'cm/s'; end
    
        speed = double(speed(:));
        time  = double(time(:));
    
        if isempty(speed)
            error('DrawGUI:EmptySpeed', ...
                'Speed data cannot be empty.');
        end
    
        if any(isinf(speed))
            error('DrawGUI:InvalidSpeed', ...
                'Speed data contains Inf values.');
        end
    
        if ~isempty(time)
    
            if numel(time) ~= numel(speed)
                error('DrawGUI:SpeedTimeSizeMismatch', ...
                    'Time and speed must contain the same number of elements.');
            end
    
            if any(~isfinite(time)) || any(diff(time) <= 0)
                error('DrawGUI:InvalidSpeedTime', ...
                    'The speed time vector must be finite and strictly increasing.');
            end
        end
    
        state.Speed       = speed;
        state.SpeedTime   = time;
        state.SpeedSource = source;
        state.SpeedUnits = units;
    
        updateSpeedStatus();
        updateSpeedPlot();
        syncPublicState();
    end

    function [speed, time] = getRawSpeed()
    
        speed = state.Speed;
        time  = state.SpeedTime;
    end

    function [speed, time] = getProcessedSpeed()
    
        speed = state.Speed;
        time  = state.SpeedTime;
        if strcmp(state.SpeedUnits, 'pixels/frame')
            speed = speed * data.getFrameRate()/data.behav.hd.resolution.Value;
        end
    
        if isempty(speed)
            return
        end
    
        if ~isempty(time)
            targetTime = data.behav.t(:);
            if numel(time) < 2
                error('DrawGUI:SpeedTime', 'Timestamped speed needs at least two samples.');
            end
            speed = interp1(time, speed, targetTime, 'linear', NaN);
            time = targetTime;
        else
            time = data.behav.t(:);
            if numel(speed) ~= numel(time)
                error('DrawGUI:SpeedTraceSizeMismatch', 'Untimed speed must match the behavior sample count.');
            end
        end
        if state.SmoothEnabled
            window = getSmoothWindowSamples();
    
            missing = ~isfinite(speed);
            speed = movmean(speed, window, 'omitnan', 'Endpoints', 'shrink');
            speed(missing) = NaN;
        end
    end

    function mask = generateSpeedMask()    
        if isempty(state.Speed)
            traceSize = getTraceSize();
            nSamples = prod(traceSize);
            mask = true(nSamples, 1);
            return
        end

        [speed, ~] = getProcessedSpeed();
        threshold = state.SpeedThreshold;
        switch state.SpeedOperator
            case '>'
                mask = speed > threshold;
            case '<'
                mask = speed < threshold;
            otherwise
                error('DrawGUI:InvalidSpeedOperator', ...
                    'Unsupported speed operator.');
        end
    end

    function updateSpeedStatus()
    
        if isempty(state.Speed)
            speedStatusLabel.Text = 'No speed data loaded.';
            return
        end
    
        text = sprintf( ...
            ['Samples: %d\n' ...
             'Range: %.6g to %.6g\n' ...
             'Rule: speed %s %.6g'], ...
            numel(state.Speed), ...
            min(state.Speed), ...
            max(state.Speed), ...
            state.SpeedOperator, ...
            state.SpeedThreshold);
    
        if state.SmoothEnabled
            text = sprintf( ...
                '%s\nSmoothing: moving mean, %.3g s', ...
                text, ...
                state.SmoothWindow);
        else
            text = sprintf('%s\nSmoothing: off', text);
        end
    
        speedStatusLabel.Text = text;
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

    function updateSpeedPlot()
        if isempty(state.Speed) || ~isvalid(speedPlotAxes)
            cla(speedPlotAxes);
            title(speedPlotAxes, 'No speed data loaded');
            return
        end

        [speed, x] = getProcessedSpeed();
        speedPlotAxes.XLabel.String = 'Time (s)';

        good = generateSpeedMask();
        goodSpeed = speed;
        badSpeed = speed;
        bad = ~good;
        bad = bad | circshift(bad, 1) | circshift(bad, -1);
        goodSpeed(~good) = NaN;
        badSpeed(~bad) = NaN;

        cla(speedPlotAxes);
        hold(speedPlotAxes, 'on');
        style = Shared.styles();
        speedBadLine = plot(speedPlotAxes, x, badSpeed, ...
            'Color', style.unmaskedColor, 'LineWidth', 1);
        speedGoodLine = plot(speedPlotAxes, x, goodSpeed, ...
            'Color', style.maskedColor, 'LineWidth', 1.25);
        speedThresholdLine = yline(speedPlotAxes, ...
            state.SpeedThreshold, '--', 'Threshold', ...
            'Color', style.maskPreviewThresh, 'LineWidth', 1);
        hold(speedPlotAxes, 'off');
        grid(speedPlotAxes, 'off');
        title(speedPlotAxes, state.SpeedSource, 'Interpreter', 'none');
        % legend(speedPlotAxes, [speedGoodLine speedBadLine speedThresholdLine], ...
        %     {'Good','Bad','Threshold'}, 'Location', 'best');
    end

    function [speed, time] = selectSpeedFromStruct(data, dialogTitle)
    
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
            error('DrawGUI:NoSpeedVariables', ...
                ['No numeric vector or N-by-2 numeric matrix was found ' ...
                 'in the selected MAT-file.']);
        end
    
        [selection, confirmed] = listdlg( ...
            'PromptString', 'Select speed variable:', ...
            'SelectionMode', 'single', ...
            'ListString', cellstr(names), ...
            'ListSize', [300 300], ...
            'Name', dialogTitle);
    
        if ~confirmed
            speed = double.empty(0,1);
            time  = double.empty(0,1);
            return
        end
    
        value = data.(names(selection));
    
        if isvector(value)
            speed = value(:);
            time  = double.empty(0,1);
        else
            time  = value(:,1);
            speed = value(:,2);
        end
    end
    function [speed, time] = interpretSpeedMatrix(value)
    
        value = double(value);
    
        % Remove completely empty rows introduced by headers or trailing lines.
        value = value(~all(isnan(value),2), :);
    
        if isvector(value)
            speed = value(:);
            time  = double.empty(0,1);
    
        elseif size(value,2) == 1
            speed = value(:,1);
            time  = double.empty(0,1);
    
        elseif size(value,2) == 2
            time  = value(:,1);
            speed = value(:,2);
    
        else
            error('DrawGUI:AmbiguousSpeedFile', ...
                ['The file must contain either one speed column or two ' ...
                 'columns arranged as [time, speed].']);
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
        state.SpeedOperator = speedOperatorDropDown.Value;
        state.SpeedThreshold = speedThresholdField.Value;
        state.ImportSource = importSourceDropDown.Value;
    end

    function restoreSavedState()
        if ~isfield(data.behav, 'maskParam') || ...
                ~isstruct(data.behav.maskParam) || ...
                ~isscalar(data.behav.maskParam)
            return
        end

        saved = data.behav.maskParam;
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

            if isfield(saved, 'Speed') && ~isempty(saved.Speed)
                speed = double(saved.Speed(:));
                if any(isinf(speed))
                    return
                end
                candidate.Speed = speed;
            end

            if isfield(saved, 'SpeedTime') && ~isempty(saved.SpeedTime)
                speedTime = double(saved.SpeedTime(:));
                if numel(speedTime) ~= numel(candidate.Speed) || ...
                        any(~isfinite(speedTime)) || any(diff(speedTime) <= 0)
                    return
                end
                candidate.SpeedTime = speedTime;
            end

            if isfield(saved,'SpeedUnits') && ismember(string(saved.SpeedUnits), ["cm/s","pixels/frame"])
                candidate.SpeedUnits = char(saved.SpeedUnits);
            end

            if isfield(saved, 'SpeedSource') && ...
                    (ischar(saved.SpeedSource) || ...
                    (isstring(saved.SpeedSource) && isscalar(saved.SpeedSource)))
                candidate.SpeedSource = string(saved.SpeedSource);
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

            if isfield(saved, 'SpeedOperator') && ...
                    (ischar(saved.SpeedOperator) || ...
                    (isstring(saved.SpeedOperator) && isscalar(saved.SpeedOperator))) && ...
                    any(strcmp(saved.SpeedOperator, {'>','<'}))
                candidate.SpeedOperator = char(saved.SpeedOperator);
            end

            if isfield(saved, 'SpeedThreshold') && ...
                    isnumeric(saved.SpeedThreshold) && ...
                    isscalar(saved.SpeedThreshold) && ...
                    isfinite(saved.SpeedThreshold)
                candidate.SpeedThreshold = double(saved.SpeedThreshold);
            end

            validSources = {'from Pose','from File','from Workspace'};
            if isfield(saved, 'ImportSource') && ...
                    (ischar(saved.ImportSource) || ...
                    (isstring(saved.ImportSource) && isscalar(saved.ImportSource))) && ...
                    any(strcmp(saved.ImportSource, validSources))
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
        speedOperatorDropDown.Value = state.SpeedOperator;
        speedThresholdField.Value = state.SpeedThreshold;
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
        % speed and threshold for the Behavior viewer; colored by the speed
        % rule only, without the manual rules
        if isempty(state.Speed)
            removeSpeedPreview();
        else
            [speed, time] = getProcessedSpeed();
            data.behav.maskTempSpeed = struct('t', time, 'speed', speed, ...
                'good', generateSpeedMask(), 'threshold', state.SpeedThreshold);
        end
        notify(data, 'MaskPreviewChanged');
    end

    function removeSpeedPreview()
        if isfield(data.behav, 'maskTempSpeed')
            data.behav = rmfield(data.behav, 'maskTempSpeed');
        end
    end

    function generateMaskAndClose(~, ~)
        data.behav.mask = buildCombinedMask();
        if isfield(data.behav, 'maskTemp'), data.behav = rmfield(data.behav, 'maskTemp'); end
        removeSpeedPreview();
        syncPublicState();
        notify(data, 'MaskChanged');
        close(maskFig);
    end

    function cancelAndClose(~, ~)
        close(maskFig);
    end

    function mask = buildCombinedMask()
        captureControlState();

        % The paw trace defines the authoritative mask size and sample grid.
        traceSize = getTraceSize();
        nSamples = prod(traceSize);
        fs = getFrameRate();
        time = data.behav.t(:);

        % No speed means no automatic exclusion: start with an all-good mask.
        if isempty(state.Speed)
            mask = true(nSamples, 1);
        else
            mask = generateSpeedMask();
            if numel(mask) ~= nSamples
                error('DrawGUI:SpeedTraceSizeMismatch', ...
                    ['Imported speed has %d samples, but ' ...
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
        removeSpeedPreview();
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

