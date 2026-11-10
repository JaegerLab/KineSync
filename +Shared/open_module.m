function fig = open_module(module)
% fig = Shared.open_module(module)
% Open a module window, or bring it to the front if it is open, and close
% the launcher. module: 'video' | 'ephys' | 'pose' | 'behav' (any case).

    module = lower(module);
    data = Shared.SessionData.instance();
    if isfield(data.fig, module) && isgraphics(data.fig.(module), 'figure')
        fig = data.fig.(module);
        figure(fig);
    else
        switch module
            case 'video', fig = Video.video_viewer();
            case 'ephys',   fig = Ephys.ephys_viewer();
            case 'pose',   fig = Pose.pose_viewer();
            case 'behav',  fig = Behav.behav_viewer();
            otherwise
                error('KineSync:module', 'Unknown module: %s', module);
        end
    end
    delete(findall(groot, 'Type', 'figure', 'Tag', Shared.MenuBar.LauncherTag));
end
