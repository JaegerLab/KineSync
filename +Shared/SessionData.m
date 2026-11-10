classdef SessionData < handle
    properties
        fig struct
        video struct
        pose struct
        ephys struct
        behav struct

        frameRate double = 0;
        currentTime double = 0;
        currentZoom double = [0 10];

        defaultPath char = '';      % start folder of file dialogs
        closingAll logical = false; % true while all windows close: no prompts, no reset
    end

    events
        TimeChanged         % currentTime moved
        ZoomChanged         % currentZoom moved
        InfoChanged         % time base changed: frame rate, triggers, frame count
        EphysChanged          % ephys traces changed (open, pre-process, delete)
        PoseChanged          % pose table or selection changed; carries Shared.PoseChangedData
        BehavChanged        % behavior results changed: events, selection, visibility
        MaskChanged         % behavior mask committed: Behavior recalculates events
        MaskPreviewChanged  % behavior mask preview: Behavior redraws trace colours only
        WindowsChanged      % a module window or sub-window opened or closed
    end

    properties (Access = private)
        warningState   % restored when the session ends
    end

    methods (Access = private)
        % hide constructor as private to avoid creating multiple instances
        function obj = SessionData()
            % Turn off the "ButtonDownFcn" warning when selecting axes tools,
            % for as long as the session lives: it ends with Exit all or when
            % the last module window closes, not when one of several closes.
            obj.warningState = warning('off', 'MATLAB:modes:mode:InvalidPropertySet');
        end
    end

    methods (Static)
        % use static function to ensure sharing data with 1 instance.
        function obj = instance()
            persistent singleton
            if isempty(singleton) || ~isvalid(singleton)
                singleton = Shared.SessionData();
            end
            obj = singleton;
        end
    end

    methods
        function delete(obj)
            if ~isempty(obj.warningState), warning(obj.warningState); end
        end

        function setTime(obj, t)
            if obj.currentTime ~= t
                obj.currentTime = t;
                notify(obj, 'TimeChanged');
            end
        end

        function setZoom(obj, xlims)
            if ~isequal(obj.currentZoom, xlims)
                obj.currentZoom = xlims;
                notify(obj, 'ZoomChanged');
            end
        end

        % A typed-in rate overrides the automatic one; [] or 0 returns to automatic.
        function setFrameRate(obj, value)
            if isempty(value), value = 0; end
            validateattributes(value, {'numeric'}, {'scalar','real','finite','nonnegative'});
            obj.frameRate = double(value);
            notify(obj, 'InfoChanged');
            notify(obj, 'TimeChanged');
        end

        % Manual override > synchronization > video rate > frame units.
        %   source: 'manual' | 'sync' | 'video' | 'none'
        % The synchronized rate is the median frame interval, so pauses
        % between trials do not lower it.
        function [frameRate, source] = getFrameRate(obj)
            frameRate = obj.frameRate;
            source = 'manual';
            if isscalar(frameRate) && isfinite(frameRate) && frameRate > 0, return; end
            % the synchronization counts even when all ephys data was deleted
            source = 'sync';
            if obj.isSynced()
                frameRate = 1 / median(diff(obj.ephys.sync.syncVideoTime));
                if isfinite(frameRate) && frameRate > 0, return; end
            end
            if obj.has('video')
                frameRate = obj.video.vid.FrameRate;
                source = 'video';
            else
                frameRate = 1;
                source = 'none';
            end
        end

        % Frame times (s), a column: synchronized times on the ephys clock
        % while the synchronization sets the rate, else frame/rate. A
        % typed-in rate overrides the synchronization too. A module with
        % another frame count converts its frames with the same anchors.
        function t = getFrameTimes(obj, nFrames)
            validateattributes(nFrames, {'numeric'}, {'scalar','integer','nonnegative'});
            [rate, source] = obj.getFrameRate();
            if strcmp(source, 'sync')
                s = obj.ephys.sync;
                if numel(s.syncVideoTime) == nFrames
                    t = s.syncVideoTime(:);
                else
                    t = Shared.convert_time((1:nFrames)', s.videoAnchor, s.ephysAnchor);
                end
                return;
            end
            t = (1:nFrames)' / rate;
        end

        % true when ephys.sync holds a synchronization
        function tf = isSynced(obj)
            tf = ~isempty(obj.ephys) && isfield(obj.ephys, 'sync') && ...
                isstruct(obj.ephys.sync) && isfield(obj.ephys.sync, 'syncVideoTime') && ...
                numel(obj.ephys.sync.syncVideoTime) >= 2;
        end

        % Frame counts of the open frame-based data, by module.
        function counts = frameCounts(obj)
            counts = struct();
            if obj.has('video'), counts.video = obj.video.vid.NumFrames; end
            if obj.has('pose'), counts.pose = height(obj.pose.table); end
            if obj.has('behav'), counts.behav = numel(obj.behav.paw(1).rawX); end
        end

        % Notify PoseChanged with what changed.
        %   kind: 'open' | 'edit' | 'commit' | 'preview' | 'selection' | 'close' | 'load'
        %   bodyparts: cellstr of changed body parts (may be empty)
        function notifyPose(obj, kind, bodyparts)
            if nargin < 3, bodyparts = {}; end
            notify(obj, 'PoseChanged', Shared.PoseChangedData(kind, bodyparts));
        end

        % Remember the folder of a file or folder opened or saved in a module.
        function rememberPath(obj, fileOrFolder)
            folder = fileOrFolder;
            if ~isfolder(folder), folder = fileparts(fileOrFolder); end
            if ~isempty(folder) && isfolder(folder), obj.defaultPath = folder; end
        end

        % Called by a module window after it closed. Closing the last module
        % window resets the session, unless all windows are being closed.
        function moduleClosed(obj)
            notify(obj, 'WindowsChanged');
            if obj.closingAll, return; end
            modules = fieldnames(obj.fig);
            for k = 1:numel(modules)
                if isgraphics(obj.fig.(modules{k}), 'figure'), return; end
            end
            delete(obj);
        end

        % check if data section is available
        function tf = has(obj, objectName)
            tf = false;
            switch lower(objectName)
                case 'video'
                    if ~isempty(obj.video) && isfield(obj.video, 'vid') && ~isempty(obj.video.vid)
                        tf = true;
                    end
                case 'ephys'
                    % raw or any processed data; metadata alone does not count
                    tf = ~isempty(obj.ephys) && ~isempty(Ephys.ephys_types(obj.ephys));
                case 'pose'
                    if ~isempty(obj.pose) && isfield(obj.pose, 'table') && ~isempty(obj.pose.table)
                        tf = true;
                    end
                case 'behav'
                    if ~isempty(obj.behav) && isfield(obj.behav, 'paw') && ~isempty(obj.behav.paw)
                        tf = true;
                    end
                case 'bpod'

                otherwise
                    tf = false;
            end
        end

    end
end
