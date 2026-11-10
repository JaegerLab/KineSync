function load_session(fig)
% Shared.load_session(fig)
% Choose a session .mat file and load it, replacing all module windows.
% Asks once if module windows are open. fig: window that shows dialogs.

    data = Shared.SessionData.instance();
    [filename, path] = uigetfile(fullfile(data.defaultPath, '*.mat'), 'Load session');
    drawnow; figure(fig);
    if isequal(filename, 0), return; end
    filename = fullfile(path, filename);
    try
        saved = Shared.read_session(filename);
    catch ME
        uialert(fig, ME.message, 'Load session');
        return;
    end

    windows = Shared.open_windows();
    if any(~[windows.isSub])
        answer = uiconfirm(fig, 'Loading a session closes all module windows.', 'Load session', ...
            'Options', {'Load', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, ...
            'Icon', 'warning');
        if ~strcmp(answer, 'Load'), return; end
    end
    data.rememberPath(filename);
    Shared.restore_session(saved);
end
