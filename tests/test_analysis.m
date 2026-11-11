function tests = test_analysis
% Run from repository root: results = runtests('tests'); assertSuccess(results)
tests = functiontests(localfunctions);
end

function testOnsetAndOffsetStayInsideTrace(testCase)
trace = [0;0;4;4;0];
s = Behav.detect_events(trace, true(size(trace)), 3, 10, 2.5);
verifyEqual(testCase, s.onset, 2);
verifyEqual(testCase, s.offset, 5);
end

function testMaskDoesNotBridgeEvents(testCase)
trace = [0;0;4;4;0;0;4;4;0];
mask = true(size(trace)); mask(2:6) = false;
s = Behav.detect_events(trace, mask, 3, 4);
verifyEmpty(testCase, s.rising); % frame 6 is masked: no crossing allowed
end

function testAllFalseMaskHasNoEvents(testCase)
s = Behav.detect_events([0;4;0;4;0], false(5,1), 2, 2);
for name = {'rising','falling','onset','offset','peak','valley'}
    verifyEmpty(testCase, s.(name{1}));
end
end

function testIndependentBodypartThresholds(testCase)
a = Behav.detect_events([0;0;4;4;0], true(5,1), 2, 2);
b = Behav.detect_events([10;10;14;14;10], true(5,1), 12, 2);
verifyEqual(testCase, a.rising, b.rising);
verifyEqual(testCase, a.falling, b.falling);
end

function testEtaTimeOriginAndDuplicates(testCase)
t = (10:0.01:11)';
signal = zeros(size(t)); signal(41) = 2; signal(61) = 8;
r = Behav.eta(signal, t, [10.4;10.4;10.6], 'method', 'none', 'maxLag', 0.05);
verifyEqual(testCase, r.eventNum, 3);
verifyEqual(testCase, r.y(abs(r.t)<1e-9), 4, 'AbsTol', 1e-10);
end

function testEtaConstantSignalAtRecordingEdges(testCase)
t = (0:0.01:1)';
r = Behav.eta(7*ones(size(t)), t, [0;1], 'method', 'none', 'maxLag', 0.1);
verifyEqual(testCase, r.y, 7*ones(size(r.y)), 'AbsTol', 1e-10);
end

function testEtaRejectsEmptyEventsAndGaps(testCase)
t = (0:0.01:1)';
verifyError(testCase, @()Behav.eta(ones(size(t)), t, [], 'method','none'), 'behav:eta:noEvents');
t(51:end) = t(51:end)+1;
verifyError(testCase, @()Behav.eta(ones(size(t)), t, 0.3, 'method','none'), 'behav:eta:timebase');
end

function testRepeatedControlsPreserveConstantSignal(testCase)
t = (0:0.01:1)';
for method = {'random_time','isi_shuffle','dither'}
    rng(17);
    r = Behav.eta(3*ones(size(t)), t, [0;0.4;0.4;1], ...
        'method',method{1}, 'nRep',3, 'maxLag',0.1, 'offset',0.05);
    verifyEqual(testCase, r.randomMean, 3*ones(size(r.t)), 'AbsTol',1e-10);
end
end

function testSmoothingFullAndOversizedWindows(testCase)
x = (1:5)';
for w = [1 5 20]
    actual = Shared.fastsmooth(x,w);
    verifySize(testCase,actual,size(x));
    verifyTrue(testCase,all(isfinite(actual)));
end
verifyEqual(testCase,Shared.fastsmooth(x,1),x);
end

function testSmoothingMissingSamplesDoesNotPoisonTail(testCase)
x = (1:30)'; x(5) = NaN;
y = Shared.fastsmooth(x,3);
verifyTrue(testCase,all(isfinite(y(10:end))));
end
