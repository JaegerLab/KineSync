function tests = test_review_fixes
tests = functiontests(localfunctions);
end

function testFrameClockFollowsSynchronization(testCase)
S = Shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close KineSync before running this test.');
addTeardown(testCase, @()delete(Shared.SessionData.instance()));
S.ephys = struct();
verifyEqual(testCase,S.getFrameTimes(3),[1;2;3]);   % frame units without a source
ttl = [2;2.01;2.021;2.03];
S.ephys.sync = struct('method','All frames','syncVideoTime',ttl,'videoAnchor',(1:4)', ...
    'ephysAnchor',ttl,'digitalChannelName','TTL-02','edge','rising');
[rate,source] = S.getFrameRate();
verifyEqual(testCase,source,'sync');
verifyEqual(testCase,rate,1/median(diff(ttl)),'RelTol',1e-12);
verifyEqual(testCase,S.getFrameTimes(4),ttl);
t = S.getFrameTimes(5);   % another frame count: the extra frame follows the fit
verifyEqual(testCase,t(1:4),ttl,'AbsTol',1e-12);
verifyGreaterThan(testCase,t(5),ttl(4));
verifyEqual(testCase,Shared.time_to_frame(t,[0 2.011 2.0301]),[1 2 4]);
S.setFrameRate(100);   % a typed-in rate overrides the synchronization
verifyEqual(testCase,S.getFrameTimes(3),[0.01;0.02;0.03]);
end

function testConvertTime(testCase)
sa = [1;3;5];
ta = [10;10.2;10.4005];
% linear between anchors: anchors convert exactly
verifyEqual(testCase,Shared.convert_time(sa,sa,ta),ta,'AbsTol',1e-12);
verifyEqual(testCase,Shared.convert_time(2,sa,ta),10.1,'AbsTol',1e-12);
% outside: the fit slope, continued from the end anchors
[t,info] = Shared.convert_time([0 6],sa,ta);
verifyEqual(testCase,t,[10 - info.slope, 10.4005 + info.slope],'AbsTol',1e-12);
% 'fit': the fitted line everywhere
verifyEqual(testCase,Shared.convert_time(sa,sa,ta,'Method','fit'),polyval([info.slope info.offset],sa),'AbsTol',1e-12);
verifyEqual(testCase,Shared.convert_time(2,sa,ta,'Offset',1),11.1,'AbsTol',1e-12);
verifyEqual(testCase,size(Shared.convert_time([1 2; 3 4],sa,ta)),[2 2]);
verifyError(testCase,@()Shared.convert_time(1,[1 2],[1 2 3]),'KineSync:convert_time:count');
verifyError(testCase,@()Shared.convert_time(1,1,1),'KineSync:convert_time:count');
verifyError(testCase,@()Shared.convert_time(1,[2 1],[1 2]),'KineSync:convert_time:anchors');
verifyWarning(testCase,@()Shared.convert_time(1,(1:4)',[0;1;3;3.5]),'KineSync:convert_time:residual');
end

function testGlobalUsesEventCountNotRepetitions(testCase)
t = (0:0.01:3)';
x = sin(2*pi*3*t)+0.4*cos(2*pi*7*t);
events = (0.5:0.1:2.5)';
a = Behav.eta(x,t,events,'method','global','maxLag',0.1,'nRep',1);
b = Behav.eta(x,t,events,'method','global','maxLag',0.1,'nRep',1000);
verifyEqual(testCase,a.randomStd,b.randomStd,'AbsTol',1e-12);
verifyEqual(testCase,a.randomStd,std(x)./sqrt(a.sampleCount),'AbsTol',1e-12);
verifyEqual(testCase,a.sampleCount,numel(events)*ones(size(a.t)));
end

function testNearZeroIsEstimatedFromRestRatherThanCrossingThreshold(testCase)
fs = 100;
t = (1:500)'/fs;
rest = 0.2+0.02*sin(2*pi*7*t);
movement = 12+sin(2*pi*3*t);
speed = [rest;movement;rest;movement;rest];
[threshold,info] = Behav.auto_rest_threshold(speed,fs);
verifyTrue(testCase,isfinite(threshold));
verifyGreaterThan(testCase,threshold,0.19);
verifyLessThan(testCase,threshold,0.23);
verifyGreaterThan(testCase,nnz(info.restMask),100);
verifyLessThan(testCase,max(speed(info.restMask)),1);
end

function testNoRestEstimateDoesNotInventOnsets(testCase)
[threshold,~] = Behav.auto_rest_threshold(5*ones(500,1),100);
verifyTrue(testCase,isnan(threshold));
s = Behav.detect_events([0;0;4;4;0],true(5,1),3,10,threshold);
verifyEqual(testCase,s.rising,2);
verifyEmpty(testCase,s.onset);
verifyEmpty(testCase,s.offset);
end

function testBinaryScalingUsesIndividualUnits(testCase)
channels = struct('bit_volts',{0.195,0.001},'units',{'uV','V'});
actual = Ephys.scale_binary_channels([10 10;-10 -10],channels,'uV');
verifyEqual(testCase,actual,[1.95 10000;-1.95 -10000],'AbsTol',1e-10);
verifyEqual(testCase,Ephys.scale_binary_channels(10,channels(2),'V'),0.01,'AbsTol',1e-12);
end

function testCsvRoundTripIgnoresPreviewAndFillsMissingLikelihood(testCase)
filename = [tempname '.csv'];
cleanup = onCleanup(@()delete(filename)); %#ok<NASGU>
t = table([1;2],[3;4],[0.8;0.9],[5;6],[7;8],[99;99],[88;88], ...
    'VariableNames',{'paw_x','paw_y','paw_likelihood','tail_x','tail_y','temp_x','temp_y'});
t.Properties.UserData = {'paw','tail','temp'};
t.Properties.Description = 'C:\source\pose.csv';
t = addprop(t,'Scorer','table'); t.Properties.CustomProperties.Scorer = 'test_model';
Pose.save_csv(filename,t);
loaded = Pose.read_csv(filename);
verifyEqual(testCase,height(loaded),2);
verifyEqual(testCase,width(loaded),6);
verifyEqual(testCase,loaded.paw_x,t.paw_x);
verifyEqual(testCase,loaded.tail_y,t.tail_y);
verifyTrue(testCase,all(isnan(loaded.tail_likelihood)));
verifyEqual(testCase,loaded.Properties.CustomProperties.Scorer,'test_model');
verifyFalse(testCase,any(startsWith(loaded.Properties.VariableNames,'temp_')));
end

function testLikelihoodConversionIsGradedAndRepeatable(testCase)
seg = struct('flag',[2;2;1;-1;-2;-3;0], 'len',[10;1;1;1;1;1;1], 'seedWidth',5);
p = Pose.seg_likelihood(seg);
verifyEqual(testCase,p,[0.95*ones(10,1);1;0.9;0.1;0.5;0;0.5],'AbsTol',1e-12);
verifyEqual(testCase,p,Pose.seg_likelihood(seg));
end

function testPoseChangedDataNormalisesBodyparts(testCase)
evt = Shared.PoseChangedData('edit',"paw");
verifyEqual(testCase,evt.Kind,'edit');
verifyEqual(testCase,evt.Bodyparts,{'paw'});
evt = Shared.PoseChangedData('selection');
verifyTrue(testCase,iscell(evt.Bodyparts) && isempty(evt.Bodyparts));
end
