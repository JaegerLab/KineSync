function save_behav(filename, behavData, settings, frameRate, range)
% Behav.save_behav(filename, behavData, settings, frameRate, range)
% Write the behavior data to a .mat file (-v7.3) with variables
%   fileFormat = 'KineSync behav', formatVersion = 2, and behav with fields
%     paw (name, rawX, rawY in pixels, thresh per trace), selection,
%     mask, maskParam, eta, source, filename (the pose file),
%     resolution, minInterval, frameRate, timeRange
% settings: struct with resolution (px/cm) and minInterval (s), from the viewer.
% Events, speeds and cm traces are not saved: Open recalculates them.
% range: [] (default) for the full length, or [t1 t2]: frames outside the
%        window become NaN and are masked out; the length stays the same,
%        so frames keep their numbers.

    if nargin < 5, range = []; end
    nFrames = numel(behavData.paw(1).rawX);
    out = struct();
    out.fileFormat = 'KineSync behav';
    out.formatVersion = 2;

    g = struct();
    g.paw = struct('name', {behavData.paw.name}, 'rawX', {behavData.paw.rawX}, ...
        'rawY', {behavData.paw.rawY}, 'thresh', {behavData.paw.thresh});
    g.selection = behavData.selection;
    g.mask = true(nFrames, 1);
    if isfield(behavData, 'mask'), g.mask = logical(behavData.mask(:)); end
    g.maskParam = [];
    if isfield(behavData, 'maskParam'), g.maskParam = behavData.maskParam; end
    g.eta = struct([]);
    if isfield(behavData, 'eta'), g.eta = behavData.eta; end
    g.source = behavData.source;
    g.filename = '';
    if isfield(behavData, 'filename'), g.filename = behavData.filename; end
    g.resolution = settings.resolution;
    g.minInterval = settings.minInterval;
    g.frameRate = frameRate;
    g.timeRange = range;

    if ~isempty(range)
        outside = ~(behavData.t(:) >= range(1) & behavData.t(:) <= range(2));
        for k = 1:numel(g.paw)
            g.paw(k).rawX(outside) = NaN;
            g.paw(k).rawY(outside) = NaN;
        end
        g.mask(outside) = false;
    end
    out.behav = g;
    save(filename, '-struct', 'out', '-v7.3');
end
