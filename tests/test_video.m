function tests = test_video
% Video export: marker drawing and writing frames. No GUI needed.
tests = functiontests(localfunctions);
end

function state = markers(poseX, poseY, eventT, eventX, eventY)
state.pose = struct('x', poseX, 'y', poseY);
state.events = [];
if nargin > 2, state.events = struct('t', eventT, 'x', eventX, 'y', eventY); end
end

function testPosePlusAtPixelPosition(testCase)
img = zeros(50, 60, 3, 'uint8');
out = Video.draw_markers(img, markers([30; 5], [20; 5]), 1, 0, 1);   % frame 1: x=30, y=20
verifyEqual(testCase, squeeze(out(20, 30, :))', uint8([0 255 255]));   % row = y, column = x
verifyEqual(testCase, squeeze(out(20, 33, :))', uint8([0 255 255]));   % arm: 3 px (6 pt across)
verifyEqual(testCase, squeeze(out(23, 33, :))', uint8([0 0 0]));       % between the arms
verifyEqual(testCase, nnz(any(out(:, 1:20, :), 3)), 0);
out = Video.draw_markers(img, markers([30; 5], [20; 5]), 2, 0, 1);    % frame 2 elsewhere
verifyEqual(testCase, squeeze(out(5, 5, :))', uint8([0 255 255]));
end

function testEventRingFadesWithTime(testCase)
img = zeros(40, 40, 3, 'uint8');
state = markers([], [], [1; 3], [10; 30], [10; 30]);
out = Video.draw_markers(img, state, 1, 1, 1);
verifyEqual(testCase, squeeze(out(10, 13, :))', uint8([255 0 255]));   % on the ring, alpha 1
verifyEqual(testCase, squeeze(out(10, 10, :))', uint8([0 0 0]));       % centre stays clear
a = 2 / (1 + exp(2));                                                  % 2 s away
verifyEqual(testCase, double(out(30, 33, 1)), round(255 * a));
verifyEqual(testCase, double(out(30, 33, 2)), 0);
end

function testScaleGrayAndMissing(testCase)
img = zeros(60, 60, 'uint8');                                           % grayscale frame
out = Video.draw_markers(img, markers(30, 30), 1, 0, 2);               % 2 px per point
verifyEqual(testCase, size(out), [60 60 3]);
verifyEqual(testCase, squeeze(out(30, 36, :))', uint8([0 255 255]));   % arm 6 px now
out = Video.draw_markers(img, markers(NaN, NaN, NaN, NaN, NaN), 1, 0, 1);
verifyEqual(testCase, nnz(out), 0);
end

function file = makeSource(testCase)
file = [tempname '.avi'];
addTeardown(testCase, @()deleteIfExists(file));
w = VideoWriter(file, 'Uncompressed AVI');   % odd size is allowed here
w.FrameRate = 10;
open(w);
for k = 1:20
    writeVideo(w, repmat(uint8(4*k), 65, 81, 3));   % frame k has gray level 4k; odd size, MPEG-4 needs >= 64
end
close(w);
end

function deleteIfExists(file)
if isfile(file), delete(file); end
end

function out = makeOutput(testCase)
out = [tempname '.mp4'];
addTeardown(testCase, @()deleteIfExists(out));
end

function testWritesFramesPaddedWithMarkers(testCase)
source = makeSource(testCase);
out = makeOutput(testCase);
writer = VideoWriter(out, 'MPEG-4'); writer.FrameRate = 25; writer.Quality = 80;
x = 21*ones(20, 1); y = 16*ones(20, 1);
n = Video.write_marked_video(writer, source, (5:14)', (0:19)'/10, markers(x, y), 2, @(~,~,~)true);
verifyEqual(testCase, n, 10);
r = VideoReader(out);
verifyEqual(testCase, [r.Height r.Width], [66 82]);   % padded to even
verifyEqual(testCase, r.NumFrames, 10);
verifyEqual(testCase, r.FrameRate, 25, 'AbsTol', 1e-6);
img = double(readFrame(r));
verifyGreaterThan(testCase, img(16, 21, 2), 150);     % cyan marker: green and blue high
verifyLessThan(testCase, img(16, 21, 1), 100);        % red low
verifyEqual(testCase, mean(img(40:60, 50:70, 1), 'all'), 20, 'AbsTol', 6);   % frame 5 = gray 20
end

function testAbortLeavesPlayableFile(testCase)
source = makeSource(testCase);
out = makeOutput(testCase);
writer = VideoWriter(out, 'MPEG-4');
n = Video.write_marked_video(writer, source, (1:20)', (0:19)'/10, markers(zeros(20,1), zeros(20,1)), 1, ...
    @(k,~,~)k < 3);
verifyEqual(testCase, n, 3);
verifyEqual(testCase, VideoReader(out).NumFrames, 3);
end

function testWriterClosedByCaller(testCase)
% closing the video window during an export closes the writer from outside
source = makeSource(testCase);
out = makeOutput(testCase);
writer = VideoWriter(out, 'MPEG-4');
n = Video.write_marked_video(writer, source, (1:20)', (0:19)'/10, markers(zeros(20,1), zeros(20,1)), 1, ...
    @(k,~,~)closeAt(writer, k, 4));
verifyEqual(testCase, n, 4);
verifyEqual(testCase, VideoReader(out).NumFrames, 4);
end

function ok = closeAt(writer, k, stopAt)
ok = k < stopAt;
if ~ok, close(writer); end
end
