function tests = test_behav_ui
% Desktop integration tests: require MATLAB graphics and Signal Processing Toolbox.
tests = functiontests(localfunctions);
end

function testSwitchingBodypartsAndTracesRecalculates(testCase)
assumeTrue(testCase, usejava('desktop'), 'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close KineSync before running UI tests.');
S.frameRate = 20;
Behav.behav_viewer();
cleanup = onCleanup(@()Shared.exit_all(false));
hd = S.behav.hd;
hd.bodypart.Items = {'a','b'};
hd.bodypart.ItemsData = [1 2];
hd.bodypart.Value = 1;
hd.bodypart.Enable = 'on';
hd.eventList.Items = {'rising','falling','onset','offset','peak','valley'};
hd.eventList.ItemsData = hd.eventList.Items;
hd.eventList.Value = 'rising'; hd.eventList.Enable = 'on';
hd.eventCheck.Enable = 'on';
x = repmat([0;0;4;4;0;0],20,1);
for k = 1:2
    S.behav.bodypart(k).name = hd.bodypart.Items{k};
    S.behav.bodypart(k).rawX = x+(k-1)*10;
    S.behav.bodypart(k).rawY = circshift(x,1)+(k-1)*20;
    S.behav.bodypart(k).thresh = struct('x',NaN,'y',NaN,'speed',NaN);
end
notify(S,'InfoChanged');   % Behavior recalculates on a time-base change
verifyTrue(testCase,S.behav.eventsValid);
first = S.behav.bodypart(1).rising;
% Other viewers read events through Behav.current_events, never the Behavior viewer's controls.
events = Behav.current_events(S);
verifyEqual(testCase,events.idx,first(:));
verifyEqual(testCase,events.t,S.behav.t(first(:)));
verifyEqual(testCase,events.x,S.behav.bodypart(1).rawX(first(:)));
hd.eventCheck.Value = false;
callback = hd.eventCheck.ValueChangedFcn; callback(hd.eventCheck,[]);
verifyEmpty(testCase,Behav.current_events(S));
hd.eventCheck.Value = true;
callback(hd.eventCheck,[]);
verifyNotEmpty(testCase,Behav.current_events(S));
% Mask GUI must work with the new data model (no per-body-part .trace).
verifyFalse(testCase,isfield(S.behav.bodypart,'trace'));
maskFig = Behav.mask_GUI([100 100]);
maskCleanup = onCleanup(@()delete(maskFig)); % not stored in hd: exit_all misses it
preview = findall(maskFig,'Type','uibutton','Text','Preview');
callback = preview.ButtonPushedFcn; callback(preview,[]);
verifyTrue(testCase,isfield(S.behav,'maskTemp'));
verifyEqual(testCase,S.behav.bodypart(1).rising,first);
commit = findall(maskFig,'Type','uibutton','Text','Generate Mask');
callback = commit.ButtonPushedFcn; callback(commit,[]);
verifyFalse(testCase,isfield(S.behav,'maskTemp'));
verifyTrue(testCase,all(S.behav.mask));
hd.bodypart.Value = 2;
callback = hd.bodypart.ValueChangedFcn; callback(hd.bodypart,[]);
verifyEqual(testCase,S.behav.bodypart(2).rising,first);
hd.trace.Value = 'Y';
callback = hd.trace.ValueChangedFcn; callback(hd.trace,[]);
verifyEqual(testCase,S.behav.bodypart(2).traceType,'y');
verifyFalse(testCase,any(ismember({'onset','offset'},hd.eventList.Items)));
verifyEmpty(testCase,S.behav.bodypart(2).onset);
verifyEmpty(testCase,S.behav.bodypart(2).offset);
verifyNotEqual(testCase,S.behav.bodypart(2).rising,first);
% Preview never changes committed-mask events, even when it excludes everything.
beforePreview = S.behav.bodypart(2).rising;
S.behav.maskTemp = false(size(S.behav.t));
notify(S,'MaskPreviewChanged');
verifyEqual(testCase,S.behav.bodypart(2).rising,beforePreview);
S.behav = rmfield(S.behav,'maskTemp');
% Manual threshold survives refresh and preview.
hd.bodypartThresh.Value = 99;
callback = hd.bodypartThresh.ValueChangedFcn; callback(hd.bodypartThresh,[]);
S.behav.maskTemp = false(size(S.behav.t));
notify(S,'InfoChanged');
verifyEqual(testCase,S.behav.bodypart(2).thresh.y,99);
verifyEmpty(testCase,S.behav.bodypart(2).rising);
S.behav = rmfield(S.behav,'maskTemp');
% Commit an all-false mask: calculation succeeds and every marker disappears.
S.behav.mask = false(size(S.behav.t));
notify(S,'MaskChanged');
verifyTrue(testCase,S.behav.eventsValid);
verifyEmpty(testCase,S.behav.bodypart(2).rising);
verifyEqual(testCase,hd.eventNum.Value,0);
% A failed calculation invalidates stored events and cannot expose old markers.
S.behav.mask = true(numel(S.behav.t)+1,1);
callback = hd.bodypart.ValueChangedFcn;
verifyError(testCase,@()callback(hd.bodypart,[]),'behav:maskSize');
verifyFalse(testCase,Behav.events_current(S));
verifyEmpty(testCase,Behav.current_events(S));
end

function testEphysInfoPreservesMappedChannelIdentity(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
Ephys.ephys_viewer();
cleanup = onCleanup(@()Shared.exit_all(false));
hd = S.ephys.hd;
S.ephys.raw = struct('data',zeros(101,2),'t',(0:0.01:1)','sampleRate',100);
S.ephys.analogChannels = {'raw1','raw2'};
S.ephys.displayName = pwd;
S.ephys.chMapping = table({'B';'A'},{'mapped1';'mapped2'},'VariableNames',{'Muscle','Names'});
hd.sortby.Items = {'Muscle'}; hd.sortby.Value = 'Muscle';
hd.chanList.Items = {'raw1','raw2'}; hd.chanList.ItemsData = [1 2]; hd.chanList.Value = 1;
notify(S,'InfoChanged');
verifyEqual(testCase,hd.chanList.Items(:),{'mapped2';'mapped1'});
verifyEqual(testCase,hd.chanList.Value,1);
S.frameRate = 120; notify(S,'InfoChanged');
verifyEqual(testCase,hd.chanList.Items(:),{'mapped2';'mapped1'});
verifyEqual(testCase,hd.chanList.ItemsData(:),[2;1]);
verifyEqual(testCase,hd.chanList.Value,1);
end

function testRefreshWithoutDataIsSafe(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
figures = {Ephys.ephys_viewer(), Pose.pose_viewer(), Behav.behav_viewer()};
cleanup = onCleanup(@()Shared.exit_all(false));
for k = 1:numel(figures)
    button = findall(figures{k},'Tooltip','Refresh');
    callback = button.ButtonPushedFcn; callback(button,[]);
end
verifyTrue(testCase,all(cellfun(@isgraphics,figures)));
end

function testWindowMenuAndExitAll(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
cleanup = onCleanup(@()Shared.exit_all(false));
launcher = KineSync(pwd);
verifyEqual(testCase,S.defaultPath,pwd);
poseFig = Shared.open_module('Pose');
verifyFalse(testCase,isgraphics(launcher));   % opening a module closes the launcher
behavFig = Shared.open_module('behav');
verifyEqual(testCase,Shared.open_module('pose'),poseFig);   % no second window
windowMenu = findall(behavFig,'Type','uimenu','Tag','Window');
items = flip(windowMenu.Children);
verifyEqual(testCase,{items.Text},{'Ephys','Video','Pose','Behavior','Open All','Bring All to Top'});
verifyEqual(testCase,logical([items(1:4).Checked]),[false false true true]);
verifyEqual(testCase,{items([1:5 end]).Accelerator},{'E','I','P','B','A','T'});
fileMenu = findall(behavFig,'Type','uimenu','Tag','File');
fileItems = flip(fileMenu.Children);
shortcuts = containers.Map({fileItems.Text},{fileItems.Accelerator});
verifyEqual(testCase,{shortcuts('Open'),shortcuts('Save'),shortcuts('Close')},{'O','S','W'});
% a sub-window is listed, checked, below its module, and removed when closed
S.behav.hd.maskFig = uifigure('Name','Edit Mask');
notify(S,'WindowsChanged');
items = flip(windowMenu.Children);
verifyEqual(testCase,strtrim(strrep(items(5).Text,char(160),' ')),'Edit Mask');
verifyTrue(testCase,logical(items(5).Checked));
delete(S.behav.hd.maskFig);
notify(S,'WindowsChanged');
verifyNumElements(testCase,windowMenu.Children,6);
% Open All opens the missing modules and keeps the open ones
openAll = findall(windowMenu,'Text','Open All');
callback = openAll.MenuSelectedFcn; callback(openAll,[]);
verifyEqual(testCase,sort(fieldnames(S.fig))',{'behav','ephys','pose','video'});
verifyEqual(testCase,S.fig.pose,poseFig);
% Exit all closes everything and resets the session
S.frameRate = 30;
Shared.exit_all(false);
verifyFalse(testCase,isvalid(S));
verifyFalse(testCase,isgraphics(poseFig) || isgraphics(behavFig));
verifyEmpty(testCase,findall(groot,'Type','figure','Name','KineSync Video'));
verifyEqual(testCase,Shared.SessionData.instance().frameRate,0);
end

function testSessionRestoreReplacesWindows(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
cleanup = onCleanup(@()Shared.exit_all(false));
file = [tempname '.mat'];
removeFile = onCleanup(@()delete(file));
S.frameRate = 20;
behavFig = Behav.behav_viewer();
poseFig = Pose.pose_viewer();
hd = S.behav.hd;
hd.bodypart.Items = {'a','b'}; hd.bodypart.ItemsData = [1 2]; hd.bodypart.Value = 2;
hd.bodypart.Enable = 'on';
hd.eventList.Items = {'rising','falling','onset','offset','peak','valley'};
hd.eventList.ItemsData = hd.eventList.Items;
hd.eventList.Value = 'rising'; hd.eventList.Enable = 'on';
hd.resolution.Value = 42;
x = repmat([0;0;4;4;0;0],20,1);
for k = 1:2
    S.behav.bodypart(k).name = hd.bodypart.Items{k};
    S.behav.bodypart(k).rawX = x+(k-1)*10;
    S.behav.bodypart(k).rawY = circshift(x,1)+(k-1)*20;
    S.behav.bodypart(k).thresh = struct('x',NaN,'y',NaN,'speed',NaN);
end
notify(S,'InfoChanged');
behavFig.Position = [150 160 900 450];
S.setTime(2); S.setZoom([1 3]);
Shared.write_session(file,{'behav'});   % pose stays out of the session
% change everything, then restore
hd.resolution.Value = 10; hd.bodypart.Value = 1;
S.frameRate = 50; S.setTime(4);
Shared.restore_session(Shared.read_session(file));
verifyFalse(testCase,isgraphics(behavFig) || isgraphics(poseFig));   % all windows replaced
verifyEqual(testCase,fieldnames(S.fig),{'behav'});
verifyEqual(testCase,S.fig.behav.Position,[150 160 900 450]);
verifyEqual(testCase,S.behav.hd.resolution.Value,42);
verifyEqual(testCase,S.behav.hd.bodypart.Value,2);
verifyEqual(testCase,numel(S.behav.bodypart),2);
verifyTrue(testCase,S.behav.eventsValid);
verifyEqual(testCase,[S.frameRate S.currentTime],[20 2]);
verifyEqual(testCase,S.currentZoom,[1 3]);
verifyFalse(testCase,S.closingAll);
end
function testEphysDigitalMenuAndSynchronize(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
cleanup = onCleanup(@()Shared.exit_all(false));
Ephys.ephys_viewer(); Pose.pose_viewer();
hd = S.ephys.hd; menu = hd.digital; rate = S.pose.hd.frameRate;
verifyEqual(testCase,menu.Items,{'No data'});
verifyEqual(testCase,hd.sync.Text,'Synchronize');
verifyFalse(testCase,logical(hd.sync.Enable));
verifyEqual(testCase,[rate.Value string(rate.FontAngle)],["1" "italic"]);   % automatic: frame units
% left axis, top first: event markers, preview, data, time line
verifyEqual(testCase,hd.ax.Children,[hd.eventMarker; hd.tempPlot; hd.dataPlot; hd.timeline]);
% a recording with a 100 Hz camera line and a single long pulse
t = (0:999)'/1000;
S.ephys.raw = struct('data',zeros(1000,1),'t',t,'sampleRate',1000);
S.ephys.processed = struct('data',{},'t',{},'sampleRate',{},'parameters',{});
S.ephys.analogChannels = {'A'}; S.ephys.displayName = pwd;
S.ephys.digital = Ephys.ttl_channels(t,[mod(0:999,10)'<2, t>=0.1 & t<0.9]);
notify(S,'InfoChanged'); notify(S,'EphysChanged');
verifyEqual(testCase,menu.Items,{'Digital channel:', ...
    'DIN-00: 99 TTL, 2 ms, 100 Hz','DIN-01: 1 TTL, 800 ms, - Hz'});
verifyEqual(testCase,menu.Value,0);
verifyEqual(testCase,string(hd.ax.YAxis(2).Visible),"off");
verifyFalse(testCase,logical(hd.sync.Enable));   % no frames yet
% choosing a channel draws it on the right axis; it does not synchronize
callback = menu.ValueChangedFcn;
menu.Value = 2; callback(menu,struct('PreviousValue',0));
verifyEqual(testCase,string([hd.digitalPlot.Visible hd.ax.YAxis(2).Visible]),["on" "on"]);
x = hd.digitalPlot.XData; y = hd.digitalPlot.YData;   % a step trace: level at each time
level = arrayfun(@(q)y(find(x <= q,1,'last')),[0.05 0.5 0.95]);
verifyEqual(testCase,level,[0 1 0]);
verifyFalse(testCase,isfield(S.ephys,'sync'));
% redrawing keeps the objects and their order
notify(S,'EphysChanged');
verifyEqual(testCase,hd.ax.Children,[hd.eventMarker; hd.tempPlot; hd.dataPlot; hd.timeline]);
% the first item hides the right axis
menu.Value = 0; callback(menu,struct('PreviousValue',2));
verifyEqual(testCase,string([hd.digitalPlot.Visible hd.ax.YAxis(2).Visible]),["off" "off"]);

% pose frames enable Synchronize
n = 99;
S.pose.table = table((1:n)',(1:n)',ones(n,1),'VariableNames',{'paw_x','paw_y','paw_likelihood'});
S.pose.table.Properties.UserData = {'paw'};
S.pose.seg = []; S.pose.segBodypart = '';
S.pose.hd.bodypart.Items = {'paw'}; S.pose.hd.bodypart.Enable = 'on';
notify(S,'InfoChanged'); S.notifyPose('load');
verifyTrue(testCase,logical(hd.sync.Enable));
push = hd.sync.ButtonPushedFcn; push(hd.sync,[]);
g = S.ephys.hd.syncGUI;
verifyTrue(testCase,isgraphics(g,'figure'));
verifyNotEmpty(testCase,findall(g,'Type','uilabel','Text','Video/Pose/Behavior'));
dds = findall(g,'Type','uidropdown');
channel = dds(cellfun(@(c) any(strcmp(c,'DIN-01: 1 TTL, 800 ms, - Hz')),{dds.Items}));
method = dds(cellfun(@(c) any(strcmp(c,'All frames')),{dds.Items}));
frames = findall(g,'Type','uieditfield');
syncButton = findall(g,'Type','uibutton','Text','Synchronize');
verifyEqual(testCase,channel.Value,1);   % DIN-00
verifyEqual(testCase,frames.Value,'[1:end]');
verifyNotEmpty(testCase,findall(g,'Type','uilabel','Text','99 events'));
verifyNotEmpty(testCase,findall(g,'Type','uilabel','Text','99 frames (of 99)'));
% presets
method.Value = 'Start and stop'; cb = method.ValueChangedFcn; cb(method,[]);
verifyEqual(testCase,frames.Value,'[1, end]');
method.Value = 'Manual selection'; cb(method,[]);
verifyEqual(testCase,frames.Value,'');
% counts must match: nothing changes
frames.Value = '[1:50]'; cb = frames.ValueChangedFcn; cb(frames,[]);
pushSync = syncButton.ButtonPushedFcn; pushSync(syncButton,[]);
verifyFalse(testCase,isfield(S.ephys,'sync'));
% NaN drops an event; typing makes it a manual selection
method.Value = 'All frames'; cb = method.ValueChangedFcn; cb(method,[]);
frames.Value = 'NaN 2:end'; cb = frames.ValueChangedFcn; cb(frames,[]);
verifyEqual(testCase,method.Value,'Manual selection');
verifyNotEmpty(testCase,findall(g,'Type','uilabel','Text','98 frames, 1 dropped (of 99)'));
pushSync(syncButton,[]);
s = S.ephys.sync;
rise = S.ephys.digital(1).rise;
verifyEqual(testCase,s.videoAnchor,(2:99)');
verifyEqual(testCase,s.ephysAnchor,rise(2:99));
verifyEqual(testCase,s.syncVideoTime(2:99),rise(2:99),'AbsTol',1e-12);
verifyEqual(testCase,s.syncVideoTime(1),rise(1),'AbsTol',1e-9);   % the straight line extends
verifyEqual(testCase,{s.digitalChannelName s.edge s.method s.frames}, ...
    {'DIN-00','rising','Manual selection','NaN 2:end'});
verifyEqual(testCase,S.pose.t,s.syncVideoTime,'AbsTol',1e-12);   % pose follows
% the time line and the time box show the frame shown: the nearest frame's time
S.setTime(s.syncVideoTime(5) + 0.003);
verifyEqual(testCase,hd.timeline.XData,[1 1]*s.syncVideoTime(5),'AbsTol',1e-12);
verifyEqual(testCase,hd.time.Value,s.syncVideoTime(5),'AbsTol',1e-12);
% a typed time snaps too, also within the frame already shown
hd.time.Value = s.syncVideoTime(5) + 0.002; cb = hd.time.ValueChangedFcn; cb(hd.time,[]);
verifyEqual(testCase,hd.time.Value,s.syncVideoTime(5),'AbsTol',1e-12);
hd.time.Value = s.syncVideoTime(7) - 0.002; cb(hd.time,[]);
verifyEqual(testCase,[hd.time.Value hd.timeline.XData],[1 1 1]*s.syncVideoTime(7),'AbsTol',1e-12);
verifyTrue(testCase,contains(hd.info.Text,'Synchronized: DIN-00 rising, 98 anchors'));
verifyEqual(testCase,rate.Value,100,'RelTol',1e-9);
verifyEqual(testCase,string(rate.FontAngle),"italic");
% a typed-in rate overrides the synchronization; clearing returns to it
S.setFrameRate(30);
verifyEqual(testCase,[rate.Value string(rate.FontAngle)],["30" "normal"]);
rate.Value = []; rateCallback = rate.ValueChangedFcn; rateCallback(rate,[]);
verifyEqual(testCase,S.frameRate,0);
verifyEqual(testCase,rate.Value,100,'RelTol',1e-9);
% both edges, in time order
edge = dds(cellfun(@(c) any(strcmp(c,'Rising and falling edge')),{dds.Items}));
edge.Value = 'both'; cb = edge.ValueChangedFcn; cb(edge,[]);
nEdges = numel(S.ephys.digital(1).rise) + numel(S.ephys.digital(1).fall);
verifyNotEmpty(testCase,findall(g,'Type','uilabel','Text',sprintf('%d events',nEdges)));
% closing the pose window: no frames (closingAll skips the Close? prompt)
S.closingAll = true; close(S.fig.pose); S.closingAll = false;
verifyFalse(testCase,logical(hd.sync.Enable));
% no digital channel
S.ephys.digital = S.ephys.digital([]); notify(S,'InfoChanged');
verifyEqual(testCase,menu.Items,{'No digital channel'});
end
function testEphysTypesFollowProcessingAndDeletion(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
cleanup = onCleanup(@()Shared.exit_all(false));
fig = Ephys.ephys_viewer();
hd = S.ephys.hd;
verifyEmpty(testCase,hd.datatype.Items);   % placeholder "no data"
verifyEqual(testCase,hd.datatype.Placeholder,'no data');
t = (0:1999)'/2000;   % 2 kHz: the default 500 Hz high pass is below Nyquist
S.ephys.raw = struct('data',[sin(2*pi*50*t) cos(2*pi*50*t)],'t',t,'sampleRate',2000);
S.ephys.processed = struct('data',{},'t',{},'sampleRate',{},'parameters',{});
S.ephys.analogChannels = {'A','B'}; S.ephys.displayName = pwd;
S.ephys.sync = struct('method','All frames','frames','[1:end]','syncVideoTime',(0:0.1:0.9)', ...
    'videoAnchor',(1:10)','ephysAnchor',(0:0.1:0.9)','digitalChannelName','DIN-00','edge','rising');
notify(S,'InfoChanged'); notify(S,'EphysChanged');
verifyEqual(testCase,hd.datatype.Items,{'Raw'});
verifyTrue(testCase,logical(hd.deleteType.Enable));
% pre-process Raw: the delete button is off while the window is open
preprocess = findall(fig,'Type','uibutton','Text','Pre-Process');
callback = preprocess.ButtonPushedFcn; callback(preprocess,[]);
prep = S.ephys.hd.prepGUI;
verifyFalse(testCase,logical(hd.deleteType.Enable));
rate = findall(prep,'Type','uinumericeditfield','Value',200); rate.Value = 300;
% the frequency signs show what is kept, swapped for band stop
high = findall(prep,'Type','uinumericeditfield','Value',500);
low = findall(prep,'Type','uinumericeditfield','Value',5000);
filterType = findall(prep,'Type','uidropdown');
verifyEqual(testCase,{high.ValueDisplayFormat low.ValueDisplayFormat},{'> %g Hz','< %g Hz'});
filterType.Value = 'bandstop'; callback = filterType.ValueChangedFcn; callback(filterType,[]);
verifyEqual(testCase,{high.ValueDisplayFormat low.ValueDisplayFormat},{'< %g Hz','> %g Hz'});
filterType.Value = 'highpass'; callback(filterType,[]);
apply = findall(prep,'Type','uibutton','Text','Apply & Close');
callback = apply.ButtonPushedFcn; callback(apply,[]);
verifyFalse(testCase,isgraphics(prep));
verifyTrue(testCase,logical(hd.deleteType.Enable));
verifyEqual(testCase,hd.datatype.Items,{'Raw','Processed 1'});
verifyEqual(testCase,hd.datatype.Value,'Processed 1');
p = S.ephys.processed(1);
verifyEqual(testCase,p.sampleRate,300);   % exactly the requested rate
verifyEqual(testCase,p.parameters.Source,'Raw');
verifyEqual(testCase,p.parameters.DownSampleRate,300);
verifyFalse(testCase,isfield(p.parameters,'SmoothWindow'));   % Fast smooth is off by default
% processing a processed type records it as the source
callback = preprocess.ButtonPushedFcn; callback(preprocess,[]);
prep = S.ephys.hd.prepGUI;
% the window shows the settings Processed 1 was made with; Raw shows defaults
rate = findall(prep,'Type','uinumericeditfield','Value',300);
verifyNumElements(testCase,rate,1);
hd.datatype.Value = 'Raw'; callback = hd.datatype.ValueChangedFcn; callback(hd.datatype,[]);
verifyEqual(testCase,rate.Value,200);
hd.datatype.Value = 'Processed 1'; callback(hd.datatype,[]);
verifyEqual(testCase,rate.Value,300);
check = findall(prep,'Type','uicheckbox','Text','Down sample'); check.Value = false;
check = findall(prep,'Type','uicheckbox','Text','Filter'); check.Value = false;   % 500 Hz is above Nyquist here
apply = findall(prep,'Type','uibutton','Text','Apply & Close');
callback = apply.ButtonPushedFcn; callback(apply,[]);
verifyEqual(testCase,S.ephys.processed(2).parameters.Source,'Processed 1');
verifyEqual(testCase,S.ephys.processed(2).sampleRate,300);   % no down sampling: the source's rate
verifyEqual(testCase,S.ephys.processed(2).t,S.ephys.processed(1).t);
% delete Raw, then everything: metadata stays, the placeholder returns
S.ephys = Ephys.ephys_delete(S.ephys,'Raw'); notify(S,'EphysChanged');
verifyEqual(testCase,hd.datatype.Items,{'Processed 1','Processed 2'});
verifyTrue(testCase,S.has('ephys'));
S.ephys = Ephys.ephys_delete(S.ephys,'Processed 1');
S.ephys = Ephys.ephys_delete(S.ephys,'Processed 1'); notify(S,'EphysChanged');
verifyFalse(testCase,S.has('ephys'));
verifyEmpty(testCase,hd.datatype.Items);
verifyFalse(testCase,logical(hd.deleteType.Enable));
verifyEqual(testCase,S.ephys.sync.digitalChannelName,'DIN-00');
verifyEqual(testCase,S.getFrameRate(),10,'RelTol',1e-12);   % frame timing still follows the sync
end
function testPoseTimelineStaysBelowTraces(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
cleanup = onCleanup(@()Shared.exit_all(false));
Pose.pose_viewer();
hd = S.pose.hd;
n = 50;
S.pose.table = table((1:n)',(1:n)',ones(n,1),'VariableNames',{'paw_x','paw_y','paw_likelihood'});
S.pose.table.Properties.UserData = {'paw'};
S.pose.seg = []; S.pose.segBodypart = '';
hd.bodypart.Items = {'paw'}; hd.bodypart.Enable = 'on';
% session load order: traces (PoseChanged) before the time (TimeChanged)
notify(S,'InfoChanged');
S.notifyPose('load');
notify(S,'TimeChanged');
hd = S.pose.hd;
yyaxis(hd.ax,'left');
children = allchild(hd.ax);   % first child is drawn on top; the time line is hidden from Children
verifyGreaterThan(testCase,find(children==hd.timelinePose),find(children==hd.xplot));
verifyGreaterThan(testCase,find(children==hd.timelinePose),find(children==hd.yplot));
end
function testFixShowCheckboxes(testCase)
assumeTrue(testCase,usejava('desktop'),'Run UI tests in desktop MATLAB.');
S = Shared.SessionData.instance();
assumeTrue(testCase,isempty(fieldnames(S.fig)),'Close KineSync before running UI tests.');
cleanup = onCleanup(@()Shared.exit_all(false));
checkFixShowCheckboxes(testCase);
end

% shared with a headless run: the checkboxes hide markers and triangles only
function checkFixShowCheckboxes(testCase)
S = Shared.SessionData.instance();
Pose.pose_viewer();
hd = S.pose.hd;
n = 300; t = (1:n)';
x = 100 + 50*sin(t/30); y = 200 + 30*cos(t/40);
x(100:104) = x(100:104) + 200;   % a short excursion: jumps, bad frames
S.pose.table = table(x,y,ones(n,1),'VariableNames',{'paw_x','paw_y','paw_likelihood'});
S.pose.table.Properties.UserData = {'paw'};
S.pose.seg = []; S.pose.segBodypart = '';
hd.bodypart.Items = {'paw'}; hd.bodypart.Enable = 'on';
hd.fixGUI = Pose.pose_fix_GUI([100 400]);
S.pose.hd = hd;
notify(S,'InfoChanged'); S.notifyPose('load');
boxes = findall(hd.fixGUI,'Type','uicheckbox');
labels = findobj(boxes,'Text','Show segment labels');
attn = findobj(boxes,'Text','Show attention signs');
verifyEqual(testCase,string([labels.Enable attn.Enable]),["off" "off"]);
preview = findall(hd.fixGUI,'Type','uibutton','Text','Preview');
preview.ButtonPushedFcn(preview,[]);
verifyEqual(testCase,string([labels.Enable attn.Enable]),["on" "on"]);
verifyTrue(testCase,labels.Value && attn.Value);
labels.Value = false; labels.ValueChangedFcn(labels,[]);
hd = S.pose.hd;
verifyFalse(testCase,logical(hd.fix_bad_x.Visible));
verifyTrue(testCase,logical(hd.fix_attnConflict_x.Visible));
verifyTrue(testCase,logical(hd.fix_jump_x.Visible) && logical(hd.fix_interp_x.Visible));
attn.Value = false; attn.ValueChangedFcn(attn,[]);
hd = S.pose.hd;
verifyFalse(testCase,logical(hd.fix_attnConflict_x.Visible) || logical(hd.fix_attnInterp_y.Visible));
verifyTrue(testCase,logical(hd.fix_jump_y.Visible));
end
