function save_session(fig)
% Shared.save_session(fig)
% Choose the open modules to save, then save them as a session .mat file.
% fig: window that shows dialogs, progress and alerts.

    data = Shared.SessionData.instance();
    windows = Shared.open_windows();
    windows = windows(~[windows.isSub]);
    if isempty(windows)
        uialert(fig, 'No module window is open: there is nothing to save.', 'Save session');
        return;
    end
    modules = {windows.module};
    labels = cellfun(@Shared.module_name, modules, 'UniformOutput', false);
    [selected, ok] = listdlg('Name', 'Save session', 'PromptString', 'Modules to save:', ...
        'ListString', labels, 'SelectionMode', 'multiple', ...
        'InitialValue', 1:numel(labels), 'ListSize', [200 120]);
    drawnow; figure(fig);
    if ~ok || isempty(selected), return; end

    [filename, path] = uiputfile(fullfile(data.defaultPath, '*.mat'), 'Save session');
    drawnow; figure(fig);
    if isequal(filename, 0), return; end
    filename = fullfile(path, filename);

    progbar = uiprogressdlg(fig, 'Title', 'Saving', 'Message', 'Saving session', ...
        'Indeterminate', 'on');
    closeBar = onCleanup(@()delete(progbar));   % also on errors
    Shared.write_session(filename, modules(selected));
    clear closeBar
    data.rememberPath(filename);
    uialert(fig, ['Session saved in ' filename], 'Success', 'Icon', 'success');
end
