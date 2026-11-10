function fig = sync_GUI(mousePos)
% Ephys.sync_GUI  Synchronize Video/Pose/Behavior frames to the ephys clock.
%
%   fig = Ephys.sync_GUI(mousePos)
%
% Left, Ephys: a digital channel and its edges (rising, falling, or both
% in time order) give the events. Right, Video/Pose/Behavior: a MATLAB vector
% of frame numbers, one per event, in which end is the frame count and NaN
% drops an event that has no frame (e.g. [NaN 1:end]). Its presets:
% All frames [1:end], Start and stop [1, end], Manual selection (empty;
% the brackets are optional).
%
% Synchronize requires as many vector entries as events. The kept pairs
% are the anchors: every frame gets an ephys time from Shared.convert_time
% (linear between anchors, the straight-line fit outside). The result is
% data.ephys.sync, the timeline of all frame-based modules:
%   method              'All frames' | 'Start and stop' | 'Manual selection'
%   frames              the vector as typed
%   syncVideoTime       ephys time of every frame (s)
%   videoAnchor         anchor frame numbers
%   ephysAnchor         anchor ephys times (s)
%   digitalChannelName  name of the digital channel
%   edge                'rising' | 'falling' | 'both'

    data = Shared.SessionData.instance();
    PRESETS = struct('All_frames', '[1:end]', 'Start_and_stop', '[1, end]', 'Manual_selection', '');

    %% draw GUI
    WIN_W = 460; WIN_H = 230; MENU_BAR = 22;
    mousePos(2) = mousePos(2) - WIN_H;
    fig = uifigure('Name', 'Synchronize', ...
        'Position', Shared.place_window([mousePos WIN_W WIN_H], MENU_BAR), ...
        'CloseRequestFcn', @onClose);
    Shared.MenuBar(fig, {'Open', []; 'Save', []});
    grid1 = uigridlayout(fig, [5 2], 'RowHeight', {22, 30, 30, 22, 30}, ...
        'ColumnWidth', {'1x', '1x'}, 'ColumnSpacing', 20);
    at = @(row, col) matlab.ui.layout.GridLayoutOptions('Row', row, 'Column', col);

    % left: ephys events
    uilabel(grid1, 'Text', 'Ephys', 'FontWeight', 'bold', 'Layout', at(1, 1));
    hd.channel = uidropdown(grid1, 'Items', {'No digital channel'}, 'ItemsData', 0, ...
        'Layout', at(2, 1), 'ValueChangedFcn', @(~,~)updateCounts());
    hd.edge = uidropdown(grid1, 'Items', {'Rising edge', 'Falling edge', 'Rising and falling edge'}, ...
        'ItemsData', {'rising', 'falling', 'both'}, 'Layout', at(3, 1), ...
        'ValueChangedFcn', @(~,~)updateCounts());
    hd.eventCount = uilabel(grid1, 'Text', '', 'Layout', at(4, 1));

    % right: frames, one timeline for all frame-based modules
    uilabel(grid1, 'Text', 'Video/Pose/Behavior', 'FontWeight', 'bold', 'Layout', at(1, 2));
    hd.method = uidropdown(grid1, 'Items', {'All frames', 'Start and stop', 'Manual selection'}, ...
        'Layout', at(2, 2), 'ValueChangedFcn', @(~,~)methodChanged());
    hd.frames = uieditfield(grid1, 'text', 'Value', PRESETS.All_frames, 'Layout', at(3, 2), ...
        'Tooltip', ['Frame number for each event, a MATLAB vector: end is the last frame, ' ...
        'NaN drops an event without a frame. Brackets are optional.'], ...
        'ValueChangingFcn', @(~,evt)framesEdited(evt.Value), ...
        'ValueChangedFcn', @(src,~)framesEdited(src.Value));
    hd.frameCount = uilabel(grid1, 'Text', '', 'Layout', at(4, 2));

    buttonRow = uigridlayout(grid1, [1 3], 'Padding', [0 0 0 0], ...
        'ColumnWidth', {'1x', 140, '1x'}, 'Layout', at(5, [1 2]));
    hd.sync = uibutton(buttonRow, 'Text', 'Synchronize', 'ButtonPushedFcn', @synchronize, ...
        'Layout', at(1, 2));

    showSaved();
    refresh();
    listeners = [ ...
        addlistener(data, 'EphysChanged', @(~,~)refresh()), ...
        addlistener(data, 'InfoChanged', @(~,~)refresh()), ...
        addlistener(data, 'PoseChanged', @(~,~)refresh()), ...
        addlistener(data, 'BehavChanged', @(~,~)refresh()), ...
        addlistener(data, 'WindowsChanged', @(~,~)refresh())];
    fig.DeleteFcn = @(~,~)delete(listeners);   % also when the Ephys window deletes it

    %% === lists and counts === %%
    % the settings of the current synchronization, if any
    function showSaved()
        if ~data.isSynced(), return; end
        s = data.ephys.sync;
        if isfield(s, 'edge'), hd.edge.Value = s.edge; end
        if isfield(s, 'method') && any(strcmp(s.method, hd.method.Items)), hd.method.Value = s.method; end
        if isfield(s, 'frames'), hd.frames.Value = s.frames; end
    end

    % channel list from the ephys digital channels; the selection is kept by
    % name, else the channel shown in the Ephys viewer, else the first
    function refresh()
        if ~isvalid(fig), return; end
        digital = digitalChannels();
        if isempty(digital)
            set(hd.channel, 'Items', {'No digital channel'}, 'ItemsData', 0, 'Value', 0, 'Enable', 'off');
        else
            selected = '';
            if hd.channel.Value > 0 && hd.channel.Value <= numel(hd.channel.Items)
                selected = channelName(hd.channel.Items{hd.channel.Value});
            elseif data.isSynced()
                selected = data.ephys.sync.digitalChannelName;
            end
            labels = arrayfun(@Ephys.ttl_stats, digital, 'UniformOutput', false);
            k = find(strcmp(selected, {digital.name}), 1);
            if isempty(k) && isfield(data.ephys, 'hd') && isfield(data.ephys.hd, 'digital')
                k = data.ephys.hd.digital.Value;
            end
            if isempty(k) || k < 1 || k > numel(digital), k = 1; end
            set(hd.channel, 'Items', labels, 'ItemsData', 1:numel(labels), 'Value', k, 'Enable', 'on');
        end
        updateCounts();
    end

    function updateCounts(text)
        if nargin < 1, text = hd.frames.Value; end
        events = currentEvents();
        hd.eventCount.Text = sprintf('%d events', numel(events));
        [N, countText] = frameTotal();
        if N == 0
            hd.frameCount.Text = 'No Video, Pose or Behavior data';
            hd.frameCount.FontColor = [0.8 0 0];
            hd.sync.Enable = 'off';
            return;
        end
        [frames, problem] = parseFrames(text, N);
        if ~isempty(problem)
            hd.frameCount.Text = problem;
            hd.frameCount.FontColor = [0.8 0 0];
        else
            dropped = sum(isnan(frames));
            text = sprintf('%d frames', numel(frames) - dropped);
            if dropped > 0, text = sprintf('%s, %d dropped', text, dropped); end
            hd.frameCount.Text = sprintf('%s (of %s)', text, countText);
            hd.frameCount.FontColor = [0 0 0];
            if numel(frames) ~= numel(events), hd.frameCount.FontColor = [0.8 0 0]; end
        end
        hd.sync.Enable = isempty(problem) && ~isempty(events);
    end

    function digital = digitalChannels()
        digital = struct('name', {}, 'rise', {}, 'fall', {});
        if isfield(data.ephys, 'digital'), digital = data.ephys.digital; end
    end

    % event times of the selected channel and edges, in time order
    function events = currentEvents()
        events = zeros(0, 1);
        digital = digitalChannels();
        k = hd.channel.Value;
        if k < 1 || k > numel(digital), return; end
        switch hd.edge.Value
            case 'rising',  events = digital(k).rise(:);
            case 'falling', events = digital(k).fall(:);
            otherwise,      events = sort([digital(k).rise(:); digital(k).fall(:)]);
        end
    end

    % Frame count of the timeline: the largest of the open modules. All
    % share the timeline; a shorter one uses its first frames.
    function [N, text] = frameTotal()
        counts = data.frameCounts();
        modules = fieldnames(counts);
        N = 0; text = '';
        if isempty(modules), return; end
        values = cellfun(@(m) counts.(m), modules);
        N = max(values);
        if all(values == N)
            text = sprintf('%d', N);
        else
            parts = cellfun(@(m) sprintf('%s %d', m, counts.(m)), modules, 'UniformOutput', false);
            text = strjoin(parts, ', ');
        end
    end

    %% === frame vector === %%
    function methodChanged()
        hd.frames.Value = PRESETS.(strrep(hd.method.Value, ' ', '_'));
        updateCounts();
    end

    % Typing something else than the preset makes it a manual selection.
    % While typing, the count follows the text (the field's Value is set
    % only when editing ends).
    function framesEdited(value)
        if ~strcmp(value, PRESETS.(strrep(hd.method.Value, ' ', '_')))
            hd.method.Value = 'Manual selection';
        end
        updateCounts(value);
    end

    %% === Synchronize === %%
    function synchronize(~, ~)
        events = currentEvents();
        N = frameTotal();
        [frames, problem] = parseFrames(hd.frames.Value, N);
        if ~isempty(problem)
            uialert(fig, problem, 'Synchronize');
            return;
        end
        k = hd.channel.Value;
        name = data.ephys.digital(k).name;
        if numel(frames) ~= numel(events)
            uialert(fig, sprintf(['%s has %d events (%s) but the frame vector has %d entries. ' ...
                'They must match: select frames, or use NaN for events without a frame.'], ...
                name, numel(events), lower(hd.edge.Items{strcmp(hd.edge.ItemsData, hd.edge.Value)}), ...
                numel(frames)), 'Synchronize');
            return;
        end
        keep = ~isnan(frames);
        if sum(keep) < 2
            uialert(fig, 'At least two frames must be paired with events.', 'Synchronize');
            return;
        end
        sourceAnchor = frames(keep);
        targetAnchor = events(keep);
        warnState = warning('off', 'KineSync:convert_time:residual');
        restoreWarning = onCleanup(@()warning(warnState));
        try
            [syncTime, info] = Shared.convert_time((1:N)', sourceAnchor, targetAnchor);
        catch ME
            uialert(fig, ME.message, 'Synchronize');
            return;
        end
        clear restoreWarning

        data.ephys.sync = struct('method', hd.method.Value, 'frames', hd.frames.Value, ...
            'syncVideoTime', syncTime, 'videoAnchor', sourceAnchor, 'ephysAnchor', targetAnchor, ...
            'digitalChannelName', name, 'edge', hd.edge.Value);
        notify(data, 'InfoChanged');
        notify(data, 'TimeChanged');

        msg = sprintf(['%d frames synchronized to %s with %d anchors. Frame rate %.4g Hz; ' ...
            'anchors are within %.3g ms of a straight line (rms %.3g ms).'], ...
            N, name, info.nAnchors, 1/median(diff(syncTime)), 1e3*info.residualMax, 1e3*info.residualRms);
        icon = 'success';
        if info.residualMax > 1e-3
            msg = [msg ' Over 1 ms: check for missing or extra pulses, or the wrong channel.'];
            icon = 'warning';
        end
        if data.frameRate > 0
            msg = sprintf(['%s The typed-in frame rate (%g Hz) still overrides it: clear the ' ...
                'frame rate field to use the synchronization.'], msg, data.frameRate);
            icon = 'warning';
        end
        uialert(fig, msg, 'Synchronize', 'Icon', icon);
    end

    function onClose(src, ~)
        delete(src);
        notify(data, 'WindowsChanged');
    end
end

% channel name from a Ephys.ttl_stats label ('TTL-02: 5502 TTL, ...')
function name = channelName(label)
    name = extractBefore(label, ': ');
    if ismissing(name), name = label; end
    name = char(name);
end

% Frame vector from text: numbers, end (= N), NaN, : , ; and arithmetic.
% Frame numbers must be whole, 1..N and increasing; NaN entries are kept.
function [frames, problem] = parseFrames(text, N)
    frames = [];
    problem = '';
    text = strtrim(char(text));
    if isempty(text)
        problem = 'Enter frame numbers, e.g. [1:end]';
        return;
    end
    expr = regexprep(text, '\<end\>', sprintf('%d', N));
    expr = regexprep(expr, '\<(NaN|nan)\>', 'NaN');
    if ~all(ismember(strrep(expr, 'NaN', ''), '0123456789 ,;:+-*/()[].eE'))
        problem = 'Use numbers, end, NaN, : , ; and + - * /';
        return;
    end
    [value, ok] = str2num(['[' expr ']']);   % characters checked above
    if ~ok || ~isnumeric(value) || ~(isvector(value) || isempty(value))
        problem = 'Not a valid MATLAB vector';
        return;
    end
    frames = double(value(:));
    numbers = frames(~isnan(frames));
    if isempty(frames)
        problem = 'No frames';
    elseif any(~isfinite(numbers) | numbers ~= round(numbers) | numbers < 1 | numbers > N)
        problem = sprintf('Frame numbers must be whole numbers from 1 to %d', N);
    elseif any(diff(numbers) <= 0)
        problem = 'Frame numbers must be increasing';
    end
end
