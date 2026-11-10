function export2base(fig)
% Shared.export2base(fig)
% Export the session data to the base workspace. fig: window that shows alerts.
    data = Shared.SessionData.instance();
    opt.WindowStyle = 'modal';
    varname = inputdlg('Enter variable name:', 'Export Variable', [1 30], {'data'}, opt);
    if ~isempty(varname)
        vars = evalin('base', 'who');
        if ismember(varname, vars)
            uialert(fig, 'Variable already exists.', 'Warning');
        else
            assignin('base', varname{1}, data);
            uialert(fig, ['Data exported as ' varname{1}], 'Success','Icon','success')
        end
    end
end
