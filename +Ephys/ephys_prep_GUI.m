function fig = ephys_prep_GUI(mousePos)
% pre process window
% The source is the data type selected in the Ephys viewer when Preview or
% Apply is clicked; Apply adds a new processed type.

    data = Shared.SessionData.instance();

    %% draw GUI
    % grid 6x3
    mousePos(2)=mousePos(2)-210;
    fig = uifigure('Name', 'Ephys Pre-Process', 'Position', Shared.place_window([mousePos 400 210]), ...
        'CloseRequestFcn', @onClose);
    grid1 = uigridlayout(fig, [6 3]);
    at = @(row, col) matlab.ui.layout.GridLayoutOptions('Row', row, 'Column', col);

    % line 1 - filter and filtfilt
    chkFilter = uicheckbox(grid1,'Text', 'Filter', 'Value', 1, 'Layout', at(1, 1), ...
        'ValueChangedFcn', @(~,~)updateEnable());
    chkFiltFilt = uicheckbox(grid1, 'Text', 'FiltFilt', 'Value', 0, 'Layout', at(1, 2));

    % line 2 - filter type, high pass and low pass frequencies
    ddFilterType = uidropdown(grid1, 'Items', {'High pass', 'Low pass', 'Band pass', 'Band stop'}, ...
        'ItemsData', {'highpass', 'lowpass', 'bandpass', 'bandstop'}, 'Value', 'highpass', ...
        'Layout', at(2, 1), 'ValueChangedFcn', @(~,~)updateEnable());
    editHighPass = uieditfield(grid1, 'numeric', 'Value', 500, 'Layout', at(2, 2));
    editLowPass = uieditfield(grid1, 'numeric', 'Value', 5000, 'Layout', at(2, 3));

    % line 3 - rectify
    chkRectify = uicheckbox(grid1,'Text', 'Rectify', 'Value',1, 'Layout', at(3, 1));

    % line 4 - moving average smooth
    chkSmooth = uicheckbox(grid1, 'Text', 'Fast smooth', 'Value', 0, 'Layout', at(4, 1), ...
        'ValueChangedFcn', @(~,~)updateEnable());
    editSmooth = uieditfield(grid1, 'numeric', 'Value', 250, 'Limits', [1 Inf], ...
        'RoundFractionalValues', 'on', 'ValueDisplayFormat', 'Moving average window: %g samples', ...
        'Layout', at(4, [2 3]));

    % line 5 - downsample
    chkDownSample = uicheckbox(grid1,'Text', 'Down sample', 'Value',1, 'Layout', at(5, 1), ...
        'ValueChangedFcn', @(~,~)updateEnable());
    editDownRate = uieditfield(grid1, 'numeric', 'Value', 200, ...
        'ValueDisplayFormat', 'Sample rate: %g Hz', 'Layout', at(5, [2 3]));

    % line 6 - buttons: preview, save&close, cancel
    uibutton(grid1, 'Text','Preview', 'ButtonPushedFcn', @preview, 'Layout', at(6, 1));
    uibutton(grid1, 'Text','Apply & Close', 'ButtonPushedFcn', @saveClose, 'Layout', at(6, 2));
    uibutton(grid1, 'Text','Cancel', 'ButtonPushedFcn', @cancelClose, 'Layout', at(6, 3));

    % show the settings of the selected data type: those it was made with
    % (processed), or the defaults (raw)
    defaults = getParameters();   % before updateEnable, so both frequencies are in
    % kept apart: a SmoothWindow field in defaults would switch Fast smooth on
    defaultSmoothWindow = editSmooth.Value;
    updateEnable();
    lastType = '';
    typeListener = addlistener(data, 'EphysChanged', @(~,~)showTypeParameters());
    showTypeParameters();
    drawnow

    function showTypeParameters()
        if ~isvalid(fig) || ~data.has('ephys'), return; end
        type = data.ephys.hd.datatype.Value;
        if strcmp(type, lastType), return; end   % e.g. after a preview
        lastType = type;
        parameters = defaults;
        k = sscanf(type, 'Processed %d');
        if ~isempty(k) && k <= numel(data.ephys.processed) && ...
                isstruct(data.ephys.processed(k).parameters) && ...
                ~isempty(data.ephys.processed(k).parameters)
            parameters = data.ephys.processed(k).parameters;
        end
        setParameters(parameters);
    end

    % inverse of getParameters; missing values keep the defaults
    function setParameters(p)
        hasHigh = isfield(p, 'HighPassFreq');
        hasLow = isfield(p, 'LowPassFreq');
        chkFilter.Value = isfield(p, 'FilterType') || hasHigh || hasLow;
        if isfield(p, 'FilterType')
            ddFilterType.Value = p.FilterType;
        elseif hasHigh && hasLow   % same inference as Ephys.ephys_prep
            ddFilterType.Value = 'bandpass';
        elseif hasLow
            ddFilterType.Value = 'lowpass';
        else
            ddFilterType.Value = 'highpass';
        end
        editHighPass.Value = defaults.HighPassFreq;
        if hasHigh, editHighPass.Value = p.HighPassFreq; end
        editLowPass.Value = defaults.LowPassFreq;
        if hasLow, editLowPass.Value = p.LowPassFreq; end
        chkFiltFilt.Value = defaults.FiltFilt;
        if isfield(p, 'FiltFilt'), chkFiltFilt.Value = p.FiltFilt; end
        chkRectify.Value = isfield(p, 'Rectify') && p.Rectify;
        chkSmooth.Value = isfield(p, 'SmoothWindow');
        editSmooth.Value = defaultSmoothWindow;
        if chkSmooth.Value, editSmooth.Value = p.SmoothWindow; end
        chkDownSample.Value = isfield(p, 'DownSampleRate');
        editDownRate.Value = defaults.DownSampleRate;
        if chkDownSample.Value, editDownRate.Value = p.DownSampleRate; end
        updateEnable();
    end

    % filter settings only with Filter on, and only the frequencies the
    % filter type uses. The signs show the frequencies kept: > high pass,
    % < low pass, and the other way round for band stop.
    function updateEnable()
        on = chkFilter.Value;
        type = ddFilterType.Value;
        ddFilterType.Enable = on;
        chkFiltFilt.Enable = on;
        editHighPass.Enable = on && ~strcmp(type, 'lowpass');
        editLowPass.Enable = on && ~strcmp(type, 'highpass');
        signs = '><';
        if strcmp(type, 'bandstop'), signs = '<>'; end
        editHighPass.ValueDisplayFormat = [signs(1) ' %g Hz'];
        editLowPass.ValueDisplayFormat = [signs(2) ' %g Hz'];
        editSmooth.Enable = chkSmooth.Value;
        editDownRate.Enable = chkDownSample.Value;
    end

    function preview(~,~)
        if ~data.has('ephys'), return; end
        src = Ephys.ephys_source(data.ephys, data.ephys.hd.datatype.Value);
        ch = data.ephys.hd.chanList.Value(1);

        % only process 1 channel for speed
        parameters = getParameters();
        if ~validFor(src, parameters), return; end
        [newData, newT] = ...
            Ephys.ephys_prep(src.data(:,ch), src.t, parameters, src.sampleRate);
        data.ephys.temp.data = newData;
        data.ephys.temp.t = newT;

        notify(data, 'EphysChanged');
    end

    function saveClose(~,~)
        if ~data.has('ephys'), close(fig); return; end
        source = data.ephys.hd.datatype.Value;
        src = Ephys.ephys_source(data.ephys, source);
        % process all channels
        parameters = getParameters();
        if ~validFor(src, parameters), return; end
        [processedData, processedT] = ...
            Ephys.ephys_prep(src.data, src.t, parameters, src.sampleRate);
        processedFs = src.sampleRate;
        if isfield(parameters, 'DownSampleRate'), processedFs = parameters.DownSampleRate; end
        parameters.Source = source;
        data.ephys.processed(end+1) = struct('data', processedData, 't', processedT, ...
            'sampleRate', processedFs, 'parameters', parameters);

        % show the new type
        types = Ephys.ephys_types(data.ephys);
        data.ephys.hd.datatype.Items = types;
        data.ephys.hd.datatype.Value = types{end};

        close(fig);
    end

    function parameters = getParameters()
        % save parameters
        parameters = struct();

        if chkFilter.Value
            parameters.FilterType = ddFilterType.Value;
            if editHighPass.Enable
                parameters.HighPassFreq = editHighPass.Value;
            end
            if editLowPass.Enable
                parameters.LowPassFreq = editLowPass.Value;
            end
            parameters.FiltFilt = chkFiltFilt.Value;
        end
        parameters.Rectify = chkRectify.Value;
        if chkSmooth.Value
            parameters.SmoothWindow = editSmooth.Value;
        end
        if chkDownSample.Value
            parameters.DownSampleRate = editDownRate.Value;
        end
    end

    % Frequencies must fit the source's rate (processed data may be slow).
    function ok = validFor(src, parameters)
        nyquist = src.sampleRate / 2;
        problems = {};
        if isfield(parameters, 'HighPassFreq') && parameters.HighPassFreq >= nyquist
            problems{end+1} = sprintf('High pass %g Hz', parameters.HighPassFreq);
        end
        if isfield(parameters, 'LowPassFreq') && parameters.LowPassFreq >= nyquist
            problems{end+1} = sprintf('Low pass %g Hz', parameters.LowPassFreq);
        end
        if isfield(parameters, 'DownSampleRate') && parameters.DownSampleRate > src.sampleRate
            problems{end+1} = sprintf('Down sample %g Hz', parameters.DownSampleRate);
        end
        ok = isempty(problems);
        if ok && isfield(parameters, 'HighPassFreq') && isfield(parameters, 'LowPassFreq') && ...
                parameters.HighPassFreq == parameters.LowPassFreq
            uialert(fig, 'High and Low must differ for a band filter.', 'Pre-Process');
            ok = false;
        elseif ~ok
            uialert(fig, sprintf('%s: too high for the selected data (%g Hz, Nyquist %g Hz).', ...
                strjoin(problems, ', '), src.sampleRate, nyquist), 'Pre-Process');
        end
        if ok, ok = smoothCoversDownSample(src, parameters); end
    end

    % A smooth window shorter than the spacing of the down-sampled points
    % skips samples, so fast changes alias. Ask before going on; e.g. a low
    % pass filter may already have removed them.
    function ok = smoothCoversDownSample(src, parameters)
        ok = true;
        if ~isfield(parameters, 'SmoothWindow') || ~isfield(parameters, 'DownSampleRate'), return; end
        spacing = src.sampleRate / parameters.DownSampleRate;
        if parameters.SmoothWindow >= spacing, return; end
        answer = uiconfirm(fig, sprintf(['The %g-sample smooth window is shorter than the %g samples ' ...
            'between down-sampled points (%g Hz to %g Hz), so some samples are skipped and fast ' ...
            'changes alias. Without Fast smooth, the window is %g samples (2.5 times the spacing).'], ...
            parameters.SmoothWindow, spacing, src.sampleRate, parameters.DownSampleRate, ...
            max(1, round(2.5 * spacing))), 'Pre-Process', ...
            'Options', {'Process anyway', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
            'Icon', 'warning');
        ok = strcmp(answer, 'Process anyway');
    end

    function cancelClose(~,~)
        close(fig);
    end

    function onClose(src,~)
        delete(typeListener);
        if isfield(data.ephys, 'temp')
            data.ephys = rmfield(data.ephys, 'temp');
        end
        delete(src)
        notify(data, 'EphysChanged');   % also re-enables the delete button
        notify(data, 'WindowsChanged');
    end
end

