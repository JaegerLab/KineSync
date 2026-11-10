function saved = read_session(filename)
% saved = Shared.read_session(filename)
% Load a session .mat file and check its format. Errors:
%   KineSync:session:format  not a session file (also sessions saved before
%                            format version 3, which carry no format marker,
%                            and StepSync sessions)
%   KineSync:session:newer   saved by a newer KineSync
%   KineSync:session:older   an older format version (before 5, frame
%                            timing came from ephys.trigger, now replaced
%                            by ephys.sync)
%   KineSync:zoom            zoom limits not increasing

    VERSION = 5;
    saved = load(filename);
    [~, name, ext] = fileparts(filename);
    name = [name ext];

    if ~isfield(saved, 'fileFormat') || ~isequal(saved.fileFormat, 'KineSync session') || ...
            ~isfield(saved, 'formatVersion')
        error('KineSync:session:format', ...
            '%s is not a KineSync session file, or was saved by an older version.', name);
    end
    if saved.formatVersion > VERSION
        error('KineSync:session:newer', ...
            '%s was saved by a newer KineSync (format %g; this version reads format %d).', ...
            name, saved.formatVersion, VERSION);
    elseif saved.formatVersion < VERSION
        error('KineSync:session:older', ...
            '%s has an older session format (%g); this version reads format %d.', ...
            name, saved.formatVersion, VERSION);
    end

    required = {'frameRate', 'currentTime', 'currentZoom', 'figures'};
    if ~all(isfield(saved, required))
        error('KineSync:session:format', '%s is incomplete: %s missing.', name, ...
            strjoin(required(~isfield(saved, required)), ', '));
    end
    unknown = setdiff(fieldnames(saved.figures), {'video', 'ephys', 'pose', 'behav'});
    if ~isempty(unknown)
        error('KineSync:session:format', '%s has unknown modules: %s.', name, strjoin(unknown, ', '));
    end
    validateattributes(saved.frameRate, {'numeric'}, {'scalar','finite','nonnegative'});
    validateattributes(saved.currentTime, {'numeric'}, {'scalar','finite','nonnegative'});
    validateattributes(saved.currentZoom, {'numeric'}, {'vector','numel',2,'finite'});
    if saved.currentZoom(2) <= saved.currentZoom(1)
        error('KineSync:zoom', 'Saved zoom limits must be increasing.');
    end
end
