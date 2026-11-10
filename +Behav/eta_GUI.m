function fig = eta_GUI(mousePos)
% Behav.eta_GUI  Event-Triggered Average parameter & history GUI
%
%   fig = Behav.eta_GUI(mousePos)
%
%   Opens a window near mousePos that lets the user:
%     • Tune ETA parameters and compute on demand (Plot button)
%     • Browse a history of runs via a dropdown
%     • Restore parameters + replot any previous run (no recompute)
%     • Delete individual runs or clear all history
%     • Pop the current plot out into a standalone figure


    data = Shared.SessionData.instance();

    %% ── Layout constants ─────────────────────────────────────────────────
    WIN_W = 580;
    WIN_H = 480;
    mousePos(2) = mousePos(2) - WIN_H;   % open below cursor (same convention)

    MENU_BAR = 22;
    fig = uifigure('Name', 'Event-Triggered Average', ...
        'Position', Shared.place_window([mousePos WIN_W WIN_H], MENU_BAR), ...
        'CloseRequestFcn', @onClose);
    Shared.MenuBar(fig, {'Open', []; 'Save', []});

    % Root grid: 4 rows × 2 columns
    %   Col 1 (parameters) | Col 2 (Plot button, spans rows 1-2)
    grid1 = uigridlayout(fig, [3 1], ...
        'Padding',      [10 10 10 10], ...
        'RowSpacing',   6, ...
        'ColumnSpacing', 8, ...
        'RowHeight',    {30, '1x', 30});

    %% ── Row 1: maxLag | Control checkbox | zscore checkbox ───────────
    subR1 = uigridlayout(grid1, [1 6], 'Padding', [0 0 0 0], ...
        'ColumnWidth', {100, '1x', 70,80,80,80}, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 1));

    hd.editMaxLag = uieditfield(subR1, 'numeric', ...
        'Value', 0.5, ...
        'ValueDisplayFormat', 'Max Lag: %.2f s', ...
        'Tooltip', 'Half-window width for ETA (seconds)');

    hd.ddMethod = uidropdown(subR1, ...
        'Items',     {'No control', 'Global (SEM)', 'Random time', 'ISI shuffle', 'Dither Offset'}, ...
        'ItemsData', {'none', 'global', 'random_time', 'isi_shuffle', 'dither'}, ...
        'Value',     'dither', ...
        'Tooltip', 'Method of random control', ...
        'ValueChangedFcn', @onMethodChanged);

    hd.editNRep = uieditfield(subR1, 'numeric', ...
        'Value', 100, ...
        'ValueDisplayFormat', 'nRep: %d', ...
        'Tooltip', 'Number of repetitions for random control');

    hd.editOffset = uieditfield(subR1, 'numeric', ...
        'Value', 1, ...
        'ValueDisplayFormat', 'Offset: %.1f s', ...
        'Tooltip', 'Random dither shift within [-offset, offset) (seconds)');

    hd.chkZscore = uicheckbox(subR1, ...
        'Text',  'Z-Score', ...
        'Value', false, ...
        'Tooltip', 'Plot-time z-score (does not change stored data)', ...
        'ValueChangedFcn', @onZscoreChanged);

    % ── Plot button ───────────────────────────
    hd.btnPlot = uibutton(subR1, 'Text', 'Plot', ...
        'FontSize',  14, ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @onPlot);

    %% ── Row 2: plot axes ─────────────────────────────────────────────────
    hd.ax = uiaxes(grid1, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 2, 'Column', 1));
    box(hd.ax, 'off');
    hd.ax.XGrid = 'off';
    hd.ax.YGrid = 'off';
    
    %% ── Row 3: runs dropdown | Delete | Clear All | Pop Out ─────────────
    subR3 = uigridlayout(grid1, [1 4], 'Padding', [0 0 0 0], ...
        'ColumnWidth', {'1x', 40, 40, 40}, ...
        'Layout', matlab.ui.layout.GridLayoutOptions('Row', 3, 'Column', 1));

    hd.ddRuns = uidropdown(subR3, ...
        'Items',    {}, ...
        'ItemsData', {}, ...
        'Placeholder', '(no runs yet)', ...
        'ValueChangedFcn', @onRunSelected);

    uibutton(subR3, 'Text', '🗑️', ...
        'Tooltip', 'Delete selected', ...
        'ButtonPushedFcn', @onDelete);

    uibutton(subR3, 'Text', '⃠', ...
        'Tooltip', 'Clear all', ...
        'ButtonPushedFcn', @onClearAll);

    uibutton(subR3, 'Text', '[➜', ...
        'Tooltip', 'Pop out', ...
        'ButtonPushedFcn', @onPopOut);

    % rebuild dropdown menu items if there were history data
    rebuildDropdown();
    % Apply initial greying-out rules
    applyGreyOut();

    drawnow
    onRunSelected(hd.ddRuns, []);

    %% ═══════════════════════════════════════════════════════════════════
    %% ── Callbacks ────────────────────────────────────────────────────
    %% ═══════════════════════════════════════════════════════════════════

    function onMethodChanged(~, ~)
        applyGreyOut();
    end

    % ── Main Plot button ──────────────────────────────────────────────────
    function onPlot(~, ~)
        if ~data.has('behav')
            uialert(fig, 'No behavior data loaded.', 'Error');
            return;
        end
        if ~data.has('ephys')
            uialert(fig, 'No ephys data loaded. Load ephys data first.', 'Error');
            return;
        end

        %% Pull live selections from behav_viewer and ephys_viewer
        gHd = data.behav.hd;

        % ephys channel & type
        ephysType = data.ephys.hd.datatype.Value;
        channel = data.ephys.hd.chanList.Value;
        src  = Ephys.ephys_source(data.ephys, ephysType);
        signal  = src.data(:, channel);
        signalT = src.t;

        if ~Behav.events_current(data)
            uialert(fig, 'Events are not current. Recalculate the selected paw first.', 'Error');
            return;
        end
        % Paw / event selection
        pawIdx   = gHd.pawList.Value;
        eventName = gHd.eventList.Value;
        eventIdx  = data.behav.paw(pawIdx).(eventName);
        eventT    = data.behav.t(eventIdx);

        % Channel name for label
        chanItems = data.ephys.hd.chanList.Items;
        chanData  = data.ephys.hd.chanList.ItemsData;
        if iscell(chanData)
            idx = cellfun(@(x) isequal(x, channel), chanData);
        else
            idx = chanData == channel;
        end
        if any(idx)
            ephysChanName = chanItems{find(idx, 1)};
        else
            ephysChanName = num2str(channel);
        end

        pawName   = data.behav.paw(pawIdx).name;
        traceName = gHd.trace.Value;

        %% Collect GUI parameters
        maxLag   = hd.editMaxLag.Value;
        method    = hd.ddMethod.Value;
        nRep      = round(hd.editNRep.Value);
        offset    = hd.editOffset.Value;
        zscore = hd.chkZscore.Value;
        nStd      = 3;   % fixed in spec; could expose later

        %% Compute ETA
        result = Behav.eta(signal, signalT, eventT, ...
            'maxLag',   maxLag, ...
            'method',    method, ...
            'nRep',      nRep, ...
            'offset',    offset, ...
            'zscore',    zscore, ...
            'nStd',      nStd, ...
            'plot',      false);

        %% Append caller-supplied metadata fields
        result.pawName     = pawName;
        result.eventName    = eventName;
        result.traceName   = traceName;
        result.ephysType     = ephysType;
        result.ephysChan     = channel;
        result.ephysChanName = ephysChanName;

        %% Save to data store (grow the array)
        if ~isfield(data.behav, 'eta') || isempty(data.behav.eta)
            data.behav.eta    = result;
            newIdx = 1;
        else
            % Older saved runs predate per-lag event counts.
            if ~isfield(data.behav.eta, 'sampleCount')
                [data.behav.eta.sampleCount] = deal([]);
            end
            result = orderfields(result, data.behav.eta);
            data.behav.eta(end + 1) = result;
            newIdx = numel(data.behav.eta);
        end

        %% Add entry to dropdown
        label = makeLabel(result);
        currentItems     = hd.ddRuns.Items;
        currentItemsData = hd.ddRuns.ItemsData;
        if isempty(currentItemsData)
            currentItemsData = {};
        end
        hd.ddRuns.Items     = [currentItems, {label}];
        hd.ddRuns.ItemsData = [currentItemsData, {newIdx}];
        hd.ddRuns.Value     = newIdx;

        %% Plot into our axis
        Behav.plot_eta(result, hd.ax);
        title(hd.ax, label, 'Interpreter', 'none');
    end

    function onZscoreChanged(src, ~)
        if isempty(hd.ddRuns.Items)
            return;
        end
        idx = hd.ddRuns.Value;
        result = data.behav.eta(idx);

        if src.Value ~= result.zscore
            % change data zscore flag
            result.zscore = src.Value;
            data.behav.eta(idx).zscore = src.Value;

            % change plot
            Behav.plot_eta(result, hd.ax);
            
            % change title
            label = makeLabel(result);
            title(hd.ax, label, 'Interpreter', 'none');
            hd.ddRuns.Items{idx} = label;
        end
    end

    % ── Dropdown selection: restore params & replot ───────────────────────
    function onRunSelected(src, ~)
        if isempty(src.Items)
            return;
        end
        idx    = src.Value;
        result = data.behav.eta(idx);

        % Restore parameter widgets
        hd.editMaxLag.Value  = result.maxLag;
        hd.chkZscore.Value = result.zscore;
        hd.editNRep.Value    = result.nRep;
        hd.editOffset.Value  = result.offset;

        % Restore method dropdown
        if ismember(result.method, hd.ddMethod.ItemsData)
            hd.ddMethod.Value = result.method;
        end

        applyGreyOut();

        % Replot from stored data — no recompute
        Behav.plot_eta(result, hd.ax);
        title(hd.ax, makeLabel(result), 'Interpreter', 'none');
    end

    % ── Delete current run ────────────────────────────────────────────────
    function onDelete(~, ~)
        if isempty(hd.ddRuns.Items)
            return;
        end
        selIdx = hd.ddRuns.Value;   % run index into data.behav.eta

        % Remove from data store
        keep = true(1, numel(data.behav.eta));
        keep(selIdx) = false;
        data.behav.eta = data.behav.eta(keep);

        % Remove from dropdown menu
        hd.ddRuns.Items(selIdx)=[];
        hd.ddRuns.ItemsData(end)=[];

        % Select adjacent run or blank axis
        n = numel(data.behav.eta);
        if n == 0
            cla(hd.ax);
            title(hd.ax, '');
        else
            newSel = min(selIdx, n);
            hd.ddRuns.Value = newSel;
            onRunSelected(hd.ddRuns, []);
        end
    end

    % ── Clear all runs ────────────────────────────────────────────────────
    function onClearAll(~, ~)
        data.behav.eta       = struct([]);   % empty struct array
        hd.ddRuns.Items     = {};
        hd.ddRuns.ItemsData = {};
        cla(hd.ax);
        title(hd.ax, '');
    end

    % ── Pop out current axis to a new figure ──────────────────────────────
    function onPopOut(~, ~)
        ax  = hd.ax;
        f   = figure();
        ax2 = copyobj(ax, f);
        ax2.Units    = 'normalized';
        ax2.Position = [0 0 1 1];
    end

    % ── Window close ─────────────────────────────────────────────────────
    function onClose(src, ~)
        % Clear the stored handle so behav_viewer knows the window is gone
        if data.has('behav') && isfield(data.behav, 'hd') && isfield(data.behav.hd, 'eta_GUI')
            data.behav.hd = rmfield(data.behav.hd, 'eta_GUI');
        end
        delete(src);
        notify(data, 'WindowsChanged');
    end

    %% ═══════════════════════════════════════════════════════════════════
    %% ── Helpers ──────────────────────────────────────────────────────
    %% ═══════════════════════════════════════════════════════════════════

    function applyGreyOut()
        method  = hd.ddMethod.Value;
        ctrlOn  = ~strcmp(method, 'none');
        isGlobal = strcmp(method, 'global');

        % Control unchecked → grey everything control-related
        % setEnable(hd.ddMethod,     ctrlOn);
        setEnable(hd.editNRep,     ctrlOn && ~isGlobal);
        setEnable(hd.chkZscore, ctrlOn);
        setEnable(hd.editOffset,   ctrlOn && strcmp(method, 'dither'));
    end

    function setEnable(widget, tf)
        if tf
            widget.Enable = 'on';
        else
            widget.Enable = 'off';
        end
    end

    function label = makeLabel(result)
        label = [result.pawName ', ' result.eventName ...
                 ' on ' result.traceName ', ' result.ephysChanName];
        if result.zscore && ~strcmp(result.method, 'none')
            label = [label ', z-score'];
        end
    end

    function rebuildDropdown()
        if isfield(data.behav, 'eta') && ~isempty(data.behav.eta)
            n = numel(data.behav.eta);
            items     = cell(1, n);
            itemsData = cell(1, n);
            for k = 1:n
                items{k}     = makeLabel(data.behav.eta(k));
                itemsData{k} = k;
            end
            hd.ddRuns.Items     = items;
            hd.ddRuns.ItemsData = itemsData;
        end
    end

end
