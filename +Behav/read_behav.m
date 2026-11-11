function g = read_behav(filename)
% g = Behav.read_behav(filename)
% Read and check a behavior .mat file written by Behav.save_behav. Errors:
%   behav:file:format  not a KineSync behavior file (StepSync gait files
%                      included), or incomplete
%   behav:file:older   an older format version
%   behav:file:newer   saved by a newer KineSync

    VERSION = 2;
    [~, name, ext] = fileparts(filename);
    name = [name ext];
    vars = who('-file', filename);
    if ~all(ismember({'fileFormat', 'formatVersion', 'behav'}, vars))
        error('behav:file:format', '%s is not a KineSync behavior file.', name);
    end
    f = load(filename, 'fileFormat', 'formatVersion', 'behav');
    if ~isequal(f.fileFormat, 'KineSync behav')
        error('behav:file:format', '%s is not a KineSync behavior file.', name);
    end
    if f.formatVersion > VERSION
        error('behav:file:newer', '%s was saved by a newer KineSync (format %g; this version reads format %d).', ...
            name, f.formatVersion, VERSION);
    elseif f.formatVersion < VERSION
        error('behav:file:older', '%s has an older behavior format (%g); this version reads format %d.', ...
            name, f.formatVersion, VERSION);
    end
    g = f.behav;

    required = {'bodypart', 'selection', 'mask', 'source', 'resolution', 'minInterval', 'frameRate'};
    missing = required(~isfield(g, required));
    if ~isempty(missing)
        error('behav:file:format', '%s is incomplete: %s missing.', name, strjoin(missing, ', '));
    end
    if isempty(g.bodypart) || ~all(isfield(g.bodypart, {'name', 'rawX', 'rawY', 'thresh'}))
        error('behav:file:format', '%s has no body parts.', name);
    end
    n = numel(g.bodypart(1).rawX);
    if any(arrayfun(@(p)numel(p.rawX) ~= n || numel(p.rawY) ~= n, g.bodypart)) || numel(g.mask) ~= n
        error('behav:file:format', '%s: body parts and mask differ in length.', name);
    end
    defaults = struct('filename', '', 'maskParam', [], 'eta', struct([]), 'timeRange', []);
    for f = fieldnames(defaults)'
        if ~isfield(g, f{1}), g.(f{1}) = defaults.(f{1}); end
    end
    if isempty(g.filename), g.filename = ''; end   % [] after a round trip
    for k = 1:numel(g.bodypart)   % files before the near-zero field: automatic
        if ~isfield(g.bodypart(k).thresh, 'nearZero'), g.bodypart(k).thresh.nearZero = NaN; end
    end
    if ~isscalar(g.selection.bodypart) || g.selection.bodypart < 1 || g.selection.bodypart > numel(g.bodypart)
        g.selection.bodypart = 1;
    end
end
