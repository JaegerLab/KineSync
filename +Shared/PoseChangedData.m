classdef PoseChangedData < event.EventData
%POSECHANGEDDATA Event data for SessionData's PoseChanged event.
%   Kind      - what happened to the pose data:
%       'open'      a new pose file replaced the table (all body parts changed)
%       'edit'      committed coordinates of existing body parts were edited
%       'commit'    a fix was committed as a body part (new or overwritten)
%       'delete'    a body part was deleted
%       'preview'   only temporary fix-preview columns changed
%       'selection' the selected body part changed; the data did not
%       'close'     the Pose viewer closed and its data was cleared
%       'load'      a session restored the pose data
%   Bodyparts - cellstr of the body parts whose committed data changed.
    properties
        Kind char
        Bodyparts cell
    end

    methods
        function obj = PoseChangedData(kind, bodyparts)
            if nargin < 2 || isempty(bodyparts), bodyparts = {}; end
            obj.Kind = char(kind);
            obj.Bodyparts = cellstr(string(bodyparts));
        end
    end
end
