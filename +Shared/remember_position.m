function remember_position(module, fig)
% Shared.remember_position(module, fig)
% Keep a closing module window's position in the MATLAB preferences, so the
% next window of that module opens there (see Shared.window_position), also
% after MATLAB restarts. A minimized window keeps the previous position.

    if ~isgraphics(fig, 'figure') || strcmp(fig.WindowState, 'minimized'), return; end
    saved = struct();
    if ispref('KineSync', 'windowPositions')
        saved = getpref('KineSync', 'windowPositions');
        if ~isstruct(saved), saved = struct(); end
    end
    saved.(module) = fig.Position;
    setpref('KineSync', 'windowPositions', saved);
end
