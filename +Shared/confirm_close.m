function tf = confirm_close(fig, module)
% tf = Shared.confirm_close(fig, module)
% Ask before closing a module window ('video', 'ephys', 'pose' or 'behav').
% No question while all windows close (Exit all, Load session) or when the
% module has no data. Ephys data whose types were all deleted still counts
% while its synchronization is kept.

    data = Shared.SessionData.instance();
    tf = data.closingAll || ~(data.has(module) || ...
        (strcmp(module, 'ephys') && data.isSynced()));
    if tf, return; end
    name = ['KineSync ' Shared.module_name(module)];
    answer = uiconfirm(fig, sprintf('Close %s?', name), 'Close', ...
        'Options', {'Close', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, ...
        'Icon', 'warning');
    tf = strcmp(answer, 'Close');
end
