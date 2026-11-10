function windows = open_windows()
% windows = Shared.open_windows()
% Open module windows, each followed by its open sub-windows.
%   windows: struct array with fields
%     module  'video' | 'ephys' | 'pose' | 'behav'
%     fig     the window
%     isSub   true for a sub-window

    data = Shared.SessionData.instance();
    modules = {'video', 'ephys', 'pose', 'behav'};
    % sub-window handles stored in data.<module>.hd
    subFields = struct('video', {{}}, 'ephys', {{'prepGUI', 'syncGUI'}}, ...
        'pose', {{'fixGUI'}}, 'behav', {{'maskFig', 'eta_GUI'}});

    windows = struct('module', {}, 'fig', {}, 'isSub', {});
    for k = 1:numel(modules)
        module = modules{k};
        if ~isfield(data.fig, module) || ~isgraphics(data.fig.(module), 'figure'), continue; end
        windows(end+1) = struct('module', module, 'fig', data.fig.(module), 'isSub', false); %#ok<AGROW>
        if ~isfield(data.(module), 'hd'), continue; end
        hd = data.(module).hd;
        for field = subFields.(module)
            if isfield(hd, field{1}) && isgraphics(hd.(field{1}), 'figure')
                windows(end+1) = struct('module', module, 'fig', hd.(field{1}), 'isSub', true); %#ok<AGROW>
            end
        end
    end
end
