function S = fix_style()
% S = Pose.fix_style()
% All display choices and attention thresholds of the fix overlay, shared
% by the Pose viewer and Pose.pose_fix(..., visualize).
% Magenta is reserved for event markers; yellow is avoided (invisible on white).
C.blueDark  = [0.00 0.24 0.62];
C.blueLight = [0.35 0.66 1.00];
C.blueGrey  = [0.66 0.80 1.00];
C.green     = [0.10 0.62 0.15];
C.red       = [0.85 0.10 0.10];
C.orange    = [1.00 0.50 0.00];
C.grey      = [0.55 0.55 0.55];
C.yellow    = [0.90 0.80 0.00];

% traces
S.xColor = C.blueDark;          % x trace
S.yColor = C.blueLight;         % y trace
S.pColor = C.yellow;          % p trace
S.leftAxisColor = [0.15 0.15 0.15];   % MATLAB default; yyaxis would recolour it
S.trace  = 1;                   % trace line width

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
S.labelLayers = {'good', 'userGood', 'bad', 'quest', 'userBad', 'unflag'};
S.attnLayers  = {'attnConflict', 'attnLongBad', 'attnInterp'};

% legend: order of the fix layers, and placement ('eastoutside' keeps it off the data)
S.legendOrder = {'interp', 'jump', 'good', 'bad', 'userGood', ...
                 'userBad', 'unflag', 'quest', 'attnConflict', 'attnLongBad', 'attnInterp'};
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
S.legend.attnConflict = 'Attn: Conflict';
S.legend.attnLongBad = 'Attn: Long bad';
S.legend.attnInterp = 'Attn: long interp';

% clicks
S.snapPx = 6;                   % ctrl-click snaps to a jump within this many pixels
end
