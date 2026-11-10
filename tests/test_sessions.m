function tests = test_sessions
% Session file format: write, read back, reject other files. No GUI needed.
tests = functiontests(localfunctions);
end

function setup(testCase)
S = Shared.SessionData.instance();
assumeTrue(testCase, isempty(fieldnames(S.fig)), 'Close KineSync before running session tests.');
% two module "windows" (plain hidden figures) with pose data and behavior data
S.fig(1).pose = figure('Visible', 'off', 'Position', [10 20 300 200]);
S.fig.behav = figure('Visible', 'off', 'Position', [30 40 500 400]);
S.pose(1).table = table((1:5)', (1:5)', ones(5,1), 'VariableNames', {'paw_x','paw_y','paw_likelihood'});
S.pose.filename = 'C:\data\pose.csv';
S.pose.hd = struct();
S.behav(1).paw = struct('name', 'paw', 'rawX', (1:5)', 'rawY', (1:5)');
S.behav.hd = struct();
S.frameRate = 30; S.currentTime = 1.5; S.currentZoom = [1 2];
S.defaultPath = tempdir;
testCase.TestData.file = [tempname '.mat'];
testCase.TestData.figs = {S.fig.pose, S.fig.behav};
addTeardown(testCase, @()teardownSession(testCase));
end

function teardownSession(testCase)
cellfun(@delete, testCase.TestData.figs);
if isfile(testCase.TestData.file), delete(testCase.TestData.file); end
delete(Shared.SessionData.instance());   % fresh session for the next test
end

function testWriteThenReadKeepsSelectedModules(testCase)
file = testCase.TestData.file;
Shared.write_session(file, {'pose'});
saved = Shared.read_session(file);
verifyEqual(testCase, saved.fileFormat, 'KineSync session');
verifyEqual(testCase, saved.formatVersion, 5);
verifyEqual(testCase, [saved.frameRate saved.currentTime saved.currentZoom], [30 1.5 1 2]);
verifyEqual(testCase, fieldnames(saved.figures), {'pose'});
verifyEqual(testCase, saved.figures.pose.Position, [10 20 300 200]);
verifyEqual(testCase, saved.pose.filename, 'C:\data\pose.csv');
verifyEqual(testCase, height(saved.pose.table), 5);
verifyFalse(testCase, isfield(saved.pose, 'hd'));
verifyTrue(testCase, isfield(saved.pose, 'parameters'));
verifyFalse(testCase, isfield(saved, 'behav'));   % not selected
verifyFalse(testCase, any(isfield(saved, {'defaultPath', 'timebaseVersion'})));
end

function testModuleWithoutDataSavesOnlyItsWindow(testCase)
file = testCase.TestData.file;
S = Shared.SessionData.instance();
S.behav = struct('hd', struct());   % window open, no paws
Shared.write_session(file, {'pose', 'behav'});
saved = Shared.read_session(file);
verifyEqual(testCase, sort(fieldnames(saved.figures)), {'behav'; 'pose'});
verifyFalse(testCase, isfield(saved, 'behav'));
end

function testRejectsOtherFiles(testCase)
file = testCase.TestData.file;
Shared.write_session(file, {'pose', 'behav'});
good = load(file);
cases = {
    rmfield(good, 'fileFormat'),                    'KineSync:session:format'
    rmfield(good, 'formatVersion'),                 'KineSync:session:format'
    setfield(good, 'fileFormat', 'KineSync Ephys'),   'KineSync:session:format' %#ok<SFLD>
    setfield(good, 'fileFormat', 'StepSync session'), 'KineSync:session:format' %#ok<SFLD>
    setfield(good, 'formatVersion', 4),             'KineSync:session:older' %#ok<SFLD>
    setfield(good, 'formatVersion', 6),             'KineSync:session:newer' %#ok<SFLD>
    rmfield(good, 'figures'),                       'KineSync:session:format'
    setfield(good, 'currentZoom', [2 1]),           'KineSync:zoom' %#ok<SFLD>
    };
for k = 1:size(cases, 1)
    s = cases{k,1};
    save(file, '-struct', 's', '-v7.3');
    verifyError(testCase, @()Shared.read_session(file), cases{k,2}, sprintf('case %d', k));
end
end

function testRejectsSessionBeforeFormatVersion3(testCase)
file = testCase.TestData.file;
% fields of a session saved before format version 3
defaultPath = tempdir; frameRate = 30; currentTime = 0; currentZoom = [0 10];
timebaseVersion = 2; figures = struct('pose', struct('Position', [1 1 2 2]));
save(file, 'defaultPath', 'frameRate', 'currentTime', 'currentZoom', ...
    'timebaseVersion', 'figures', '-v7.3');
verifyError(testCase, @()Shared.read_session(file), 'KineSync:session:format');
end
