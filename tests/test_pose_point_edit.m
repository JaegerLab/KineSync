function tests = test_pose_point_edit
% Pose Fix with missing points (NaN) and user point edits.
tests = functiontests(localfunctions);
end

% licking-like trace: short tongue-out runs, NaN in between
function [x, y, out] = lickTrace()
N = 300; x = nan(N,1); y = x;
for s = 1:30:N-12
    k = (s:s+9)'; e = 40*sin(pi*(0:9)/9)';
    x(k) = 300 + e; y(k) = 200 + 0.3*e;
end
out = isfinite(x);
end

function testPoseFixKeepsMissingFrames(testCase)
[x, y, out] = lickTrace();
x(64) = x(64) + 150;                          % one mislabel inside a lick
[xf, yf, mask] = Pose.pose_fix(x, y, 30, 5);
verifyEqual(testCase, isfinite(xf), out);     % gaps are not filled
verifyEqual(testCase, isfinite(yf), out);
verifyFalse(testCase, mask(64));
verifyLessThan(testCase, abs(xf(64) - 340), 10); % interpolated within its lick
end

function testRunsInterpolatedSeparately(testCase)
% bad frame at the start of a run is held from its own run, not bridged
x = [1 2 3 NaN NaN 100 101 102]'; y = zeros(8,1);
mask = logical([1 1 1 0 0 0 1 1]');
xf = Pose.apply_point_edits(x, y, mask, [], []);
verifyEqual(testCase, xf(6), 101);
verifyTrue(testCase, all(isnan(xf(4:5))));
% a run without any good frame keeps its raw values
mask(7:8) = false;
xf = Pose.apply_point_edits(x, y, mask, [], []);
verifyEqual(testCase, xf(6:8), x(6:8));
end

function testAddRemoveAndLikelihood(testCase)
[x, y] = lickTrace();
[~, ~, mask, seg] = Pose.pose_fix(x, y, 30, 5);
N = numel(x);
e = Pose.point_edit([], N);
e = Pose.point_edit(e, N, 20, 'add', [310 205]);   % frame 20 was missing
e = Pose.point_edit(e, N, 5, 'remove');            % frame 5 had a point
[xf, yf, p, present] = Pose.apply_point_edits(x, y, mask, seg, e);
verifyEqual(testCase, [xf(20) yf(20)], [310 205]);
verifyEqual(testCase, p(20), 1);
verifyTrue(testCase, isnan(xf(5)) && isnan(p(5)) && ~present(5));
verifyTrue(testCase, all(isnan(p(~present))));
verifyTrue(testCase, all(isfinite(p(present))));
% add and remove replace each other
e = Pose.point_edit(e, N, 20, 'remove');
verifyTrue(testCase, e.removed(20) && isnan(e.addX(20)));
e = Pose.point_edit(e, N, 5, 'add', [1 2]);
verifyFalse(testCase, e.removed(5));
end

function testPointEditRejectsBadInput(testCase)
e = Pose.point_edit([], 10);
verifyError(testCase, @()Pose.point_edit(e, 10, 11, 'remove'), 'pose:point_edit:frame');
verifyError(testCase, @()Pose.point_edit(e, 10, 3, 'add', [NaN 1]), 'pose:point_edit:xy');
verifyError(testCase, @()Pose.point_edit(e, 12), 'pose:point_edit:size');
end

function testEditsSurviveSegmentRerun(testCase)
% the Pose viewer re-runs pose_fix after a segment edit; point edits stay
S = Shared.SessionData.instance();
assumeTrue(testCase, ~S.has('pose'), 'Close KineSync before running this test.');
cleanup = onCleanup(@()resetPose(S)); %#ok<NASGU>
[x, y] = lickTrace(); N = numel(x);
S.pose = struct();
S.pose.table = table(x, y, ones(N,1), 'VariableNames', {'tongue_x','tongue_y','tongue_likelihood'});
[~, ~, ~, seg] = Pose.pose_fix(x, y, 30, 5);
S.pose.seg = seg; S.pose.segBodypart = 'tongue';
S.pose.pointEdit = Pose.point_edit([], N, 20, 'add', [310 205]);
Pose.refresh_preview(S);
k = find(seg.flag > 0, 1); seg.flag(k) = -3; seg.isNew(k) = true;
[~, ~, ~, seg] = Pose.pose_fix(x, y, [], [], seg);
S.pose.seg = seg;
Pose.refresh_preview(S);
verifyEqual(testCase, [S.pose.table.temp_x(20) S.pose.table.temp_y(20)], [310 205]);
verifyEqual(testCase, S.pose.table.temp_likelihood(20), 1);
verifyTrue(testCase, isnan(S.pose.table.temp_likelihood(25)));   % still missing
end

function resetPose(S)
S.pose = struct();
end
