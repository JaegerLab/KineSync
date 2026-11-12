function S = styles()
% S = Shared.styles()
% Colors and other display choices shared by all modules, so each kind of
% data looks the same in every window. S.colors is the palette; the other
% fields give each plotted item its color from it.
% Magenta is reserved for event markers.
C.blueDark  = [0.00 0.24 0.62];
C.blueLight = [0.35 0.66 1.00];
C.blueGrey  = [0.66 0.80 1.00];
C.green     = [0.10 0.62 0.15];
C.red       = [0.85 0.10 0.10];
C.orange    = [1.00 0.50 0.00];
C.grey      = [0.55 0.55 0.55];
C.yellow    = [0.90 0.80 0.00];
C.black     = [0 0 0];
C.cyan      = [0 1 1];
C.magenta   = [1 0 1];
S.colors = C;

%% All modules
S.leftAxisColor = [0.15 0.15 0.15];   % MATLAB default; yyaxis would recolour it
S.timeline = C.black;                 % cursor line at the current time
S.eventColor = C.magenta;             % event circles in every viewer and the video
S.eventWidth = 2;

%% Video
S.poseMarkerColor = C.cyan;           % '+' at the selected body part
S.posePreviewColor = C.green;         % 'o' at the Pose Fix preview
S.poseMarkerWidth = 2;

%% Ephys
S.rawColor = C.blueDark;              % raw data
S.processedColor = C.green;           % processed data
S.previewColor = C.orange;            % pre-process preview
S.digitalColor = C.yellow;            % digital channel, right axis

%% Behavior and Edit Mask
S.maskedColor = C.blueDark;           % trace inside the mask (analysed)
S.unmaskedColor = C.blueGrey;         % trace outside the mask
S.threshColor = C.blueDark;           % body-part threshold (dotted)
S.maskPreviewGood = C.black;          % mask preview trace, passing the threshold
S.maskPreviewBad = C.grey;            % mask preview trace, failing it
S.maskPreviewThresh = C.black;        % mask preview trace threshold (dashed)

%% Event-triggered average
S.etaColor = C.black;                 % ETA line, control mean and band

%% Pose traces
S.xColor = C.blueDark;          % x trace
S.yColor = C.blueLight;         % y trace
S.pColor = C.yellow;            % p trace
S.trace  = 1;                   % trace line width

%% Pose Fix overlay, shared by the Pose viewer and Pose.pose_fix(..., visualize)
% interpolation (behind the trace)
S.interpColor = C.green;
S.interpStyle = ':';
S.interpWidth = 2;

% jumps (on top of the trace)
S.jumpColor = C.orange;
S.jumpStyle = '--';
S.jumpWidth = S.trace;

% frame markers; seeds made by the algorithm are not marked
S.good  = C.green;
S.bad   = C.red;
S.grey  = C.grey;
S.markSize  = 6;                % same for all frame markers
S.markWidth = 1;                % one step thicker than the default 0.5
S.goodMarker     = 'o';         % propagated good: open circle
S.userGoodMarker = 'o';         % user-made seed: filled circle
S.badMarker      = 'x';         % propagated bad
S.questMarker    = 'x';         % questionable (grey)
S.userBadMarker  = '*';         % user-made bad (user)
S.unflagMarker   = 'o';         % never reached (grey)
S.userAddMarker    = '+';       % point added in the video (green, on the fix)
S.userRemoveMarker = 's';       % point removed in the video (red, on the raw trace)

% needs attention: large circles at both ends
S.attnMarker   = '^';
S.attnSize     = 14;
S.attnWidth    = 1.5;
S.attnConflict = C.orange;      % neighbouring good segments
S.attnLongBad  = C.red;         % bad segment of at least longBadFrac * seedWidth
S.attnInterp   = C.green;       % interpolation of at least longInterpFrac * seedWidth
S.longBadFrac    = 1/3;
S.longInterpFrac = 1;

% layers the Pose auto fix checkboxes show/hide (interp and jump always show)
S.labelLayers = {'good', 'userGood', 'bad', 'quest', 'userBad', 'unflag', ...
                 'userAdd', 'userRemove'};
S.attnLayers  = {'attnConflict', 'attnLongBad', 'attnInterp'};

% legend: order of the fix layers, and placement ('eastoutside' keeps it off the data)
S.legendOrder = {'interp', 'jump', 'good', 'bad', 'userGood', ...
                 'userBad', 'userAdd', 'userRemove', 'unflag', 'quest', 'attnConflict', 'attnLongBad', 'attnInterp'};
S.legendLocation = 'southeast';

% Displaynames for legends
S.legend.x = 'X';
S.legend.y = 'Y';
S.legend.p = 'P';
S.legend.interp = 'Interpolation';
S.legend.jump = 'Jump';
S.legend.good = 'Accepted';
S.legend.bad = 'Rejected';
S.legend.quest = 'Questionable';
S.legend.unflag = 'Undetermined';
S.legend.userGood = 'User confirmed';
S.legend.userBad = 'User rejected';
S.legend.userAdd = 'User added';
S.legend.userRemove = 'User removed';
S.legend.attnConflict = 'Attn: Conflict';
S.legend.attnLongBad = 'Attn: Long bad';
S.legend.attnInterp = 'Attn: long interp';

% clicks
S.snapPx = 6;                   % ctrl-click snaps to a jump within this many pixels
end
