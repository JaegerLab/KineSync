function write_session(filename, modules)
% Shared.write_session(filename, modules)
% Write a session .mat file (-v7.3) with the given modules.
%   modules: cellstr of modules with an open window, e.g. {'pose', 'behav'}
% Each module is saved with its window position and, if it has data, its
% data and widget values (see Shared.get_param).

    data = Shared.SessionData.instance();
    out = struct();
    out.fileFormat = 'KineSync session';
    out.formatVersion = 5;   % 5: ephys.sync replaces ephys.trigger
    out.frameRate = data.frameRate;
    out.currentTime = data.currentTime;
    out.currentZoom = data.currentZoom;
    out.figures = struct();
    for k = 1:numel(modules)
        module = modules{k};
        out.figures.(module).Position = data.fig.(module).Position;
        % ephys whose data was all deleted still carries its synchronization
        if data.has(module) || (strcmp(module, 'ephys') && data.isSynced())
            saved = rmfield(data.(module), 'hd');
            saved.parameters = Shared.get_param(data.(module).hd);
            out.(module) = saved;
        end
    end
    save(filename, '-struct', 'out', '-v7.3');
end
