function jivesBRGui()
% jivesBRGui  Minimal GUI for the Jives BR online pipeline.
%
%   Start     — opens cbmex, initialises globals, starts T1/T2
%   Close All — stops T1/T2, closes cbmex, clears globals and all
%               persistent variables in the pipeline functions

%% Build window
fig = uifigure('Name',     'Jives BR Online', ...
               'Position', [200 350 360 305], ...
               'Resize',   'off', ...
               'CloseRequestFcn', @(f,~) onCloseWindow(f));

fig.UserData = struct('T1', [], 'T2', [], 'T_ui', [], 'running', false);

%% Status row
uilabel(fig, 'Position', [20 267 55 20], 'Text', 'Status:');
hStatus = uilabel(fig, 'Position', [75 267 100 20], ...
    'Text', 'Stopped', 'FontColor', [0.7 0.1 0.1]);

uilabel(fig, 'Position', [190 267 45 20], 'Text', 'Trials:');
hTrials = uilabel(fig, 'Position', [238 267 80 20], 'Text', '0');

%% Task row
uilabel(fig, 'Position', [20 233 40 22], 'Text', 'Task:');
hTask = uieditfield(fig, 'text', ...
    'Position',  [62 233 278 22], ...
    'Value',     'Waiting for task info...', ...
    'Editable',  'off', ...
    'FontColor', [0.4 0.4 0.4]);

%% Buttons
hStart = uibutton(fig, 'push', ...
    'Position',       [20 155 150 50], ...
    'Text',           'Start', ...
    'FontSize',       15, ...
    'FontWeight',     'bold', ...
    'BackgroundColor', [0.47 0.67 0.19]);
hStart.ButtonPushedFcn = @(~,~) onStart(fig, hStart, hStatus);

fig.UserData.startBtn = hStart;   % store so onCloseAll can re-enable it
fig.UserData.hTask    = hTask;    % store so onCloseAll can reset it
uibutton(fig, 'push', ...
    'Position',       [190 155 150 50], ...
    'Text',           'Close All', ...
    'FontSize',       15, ...
    'FontWeight',     'bold', ...
    'BackgroundColor', [0.85 0.33 0.10], ...
    'ButtonPushedFcn', @(~,~) onCloseAll(fig, hStatus));

%% Export section
uilabel(fig, 'Position', [20 122 320 20], ...
    'Text', 'Export Data', 'FontWeight', 'bold');
% Base export path comes from path.txt (next to this GUI); fall back to pwd.
basePath = readBasePathFile();        % '' if path.txt missing/empty
useDefaultPath = isempty(basePath);
if useDefaultPath
    basePath = pwd;
end
uilabel(fig, 'Position', [20 96 42 20], 'Text', 'Path:');
hExportPath = uieditfield(fig, 'text', ...
    'Position', [65 94 200 22], ...
    'Value',    basePath, ...
    'Tooltip',  'Base directory; comments_online/ and trials_online/ are created here');
uibutton(fig, 'push', ...
    'Position',       [270 94 70 22], ...
    'Text',           'Browse...', ...
    'ButtonPushedFcn', @(~,~) onBrowse(fig));
chkComments = uicheckbox(fig, ...
    'Position', [20 62 165 22], ...
    'Text',     'Export comments (.txt)', ...
    'Value',    true);
chkTrials = uicheckbox(fig, ...
    'Position', [200 62 150 22], ...
    'Text',     'Export trials (.csv)', ...
    'Value',    true);

fig.UserData.hExportPath = hExportPath;
fig.UserData.chkComments = chkComments;
fig.UserData.chkTrials   = chkTrials;

%% UI update timer — refreshes status, trial count, and task label every 0.5 s
T_ui = timer('Name', 'Jives_UI', 'Period', 0.5, 'ExecutionMode', 'fixedRate', ...
             'TimerFcn', @(~,~) updateLabels(fig, hStatus, hTrials, hTask));
fig.UserData.T_ui = T_ui;
start(T_ui);

% Notify the user if path.txt was empty/missing and we fell back to pwd.
if useDefaultPath
    uialert(fig, sprintf(['path.txt is empty or missing — using the current folder:\n%s\n\n' ...
        'Set your own base path in path.txt (next to jivesBRGui.m) to share across systems.'], ...
        basePath), 'Using default path', 'Icon', 'info');
end

end % jivesBRGui

%% =========================================================================

function onStart(fig, hStart, hStatus)
    ud = fig.UserData;
    if ud.running
        return
    end

    % Recording check
    answer = uiconfirm(fig, ...
        'Have you started recording in BlackRock?', ...
        'BlackRock Check', ...
        'Options',       {'Yes, continue', 'Cancel'}, ...
        'DefaultOption', 'Yes, continue', ...
        'CancelOption',  'Cancel', ...
        'Icon',          'question');
    if strcmp(answer, 'Cancel')
        return
    end

    % Check for open plot figures from a previous session
    openFigs = findobj(0, 'Type', 'figure');
    openFigs(openFigs == fig) = [];   % exclude the GUI window itself
    if ~isempty(openFigs)
        selection = uiconfirm(fig, ...
            sprintf('%d figure(s) from the previous session are still open.\nClose them now and start a new session?', numel(openFigs)), ...
            'Open Figures Detected', ...
            'Options',       {'Close Anyway', 'Back to Save'}, ...
            'DefaultOption', 'Back to Save', ...
            'CancelOption',  'Back to Save', ...
            'Icon',          'warning');
        if strcmp(selection, 'Back to Save')
            return   % user wants to save first — abort start
        end
        close(openFigs);
    end

    % Reset globals
    global trials inTrial fhComments fhTrials
    trials  = struct([]);
    inTrial = false;

    % Open streaming log files for this session (conditional on checkboxes)
    dtStr      = datestr(now, 'yyyymmdd_HHMMSS');
    dateStr    = datestr(now, 'yyyy-mm-dd');   % date subfolder name
    exportPath = fig.UserData.hExportPath.Value;
    if fig.UserData.chkComments.Value
        commentsDir = fullfile(exportPath, 'comments_online', dateStr);
        if ~isfolder(commentsDir); mkdir(commentsDir); end
        commentFile = fullfile(commentsDir, ['comments_' dtStr '.txt']);
        fhComments  = fopen(commentFile, 'w');
        fprintf('[Export] comments → %s\n', commentFile);
    else
        fhComments = [];
    end
    if fig.UserData.chkTrials.Value
        trialsDir = fullfile(exportPath, 'trials_online', dateStr);
        if ~isfolder(trialsDir); mkdir(trialsDir); end
        trialFile = fullfile(trialsDir, ['trials_' dtStr '.csv']);
        fhTrials  = fopen(trialFile, 'w');
        fprintf(fhTrials, 'Trial_number,Task,Trial_type,Start,End,Trialoutcome,Choiceoutcome,Choosen_choice,Choicetime,Target_1_presented,Target_2_presented,Target_1_pos_x,Target_1_pos_y,Target_2_pos_x,Target_2_pos_y,Requested_target_2_time_offset,Fixation_point_off\n');
        fprintf('[Export] trials   → %s\n', trialFile);
    else
        fhTrials = [];
    end

    % Connect cbmex
    try
        cbmex('open')
        cbmex('trialconfig', 1, 'double', 'absolute', 'comment', 200)
    catch ME
        uialert(fig, ME.message, 'cbmex error');
        return
    end

    % REVISED: T1 calls getJivesData with no output — completed trials are
    % appended directly to global `trials` inside getJivesData.
    T1 = timer('Name', 'Jives_Acquire', 'Period', 0.25, 'ExecutionMode', 'fixedRate', ...
               'TimerFcn', 'getJivesData();', ...            % REVISED
               'ErrorFcn', @(~,e) fprintf('[T1 error] %s\n', e.Data.message));

    % REVISED: T2 switchyard takes no argument — reads global `trials` directly.
    T2 = timer('Name', 'Jives_Plot', 'Period', 1.0, 'ExecutionMode', 'fixedRate', ...
               'TimerFcn', 'jivesAnalysisSwitchyard();', ... % REVISED
               'ErrorFcn', @(~,e) fprintf('[T2 error] %s\n', e.Data.message));

    start(T1);
    start(T2);

    ud.T1      = T1;
    ud.T2      = T2;
    ud.running = true;
    fig.UserData = ud;

    hStart.Enable = 'off';
    hStatus.Text      = 'Running';
    hStatus.FontColor = [0.17 0.51 0.10];
end

%% =========================================================================

function onCloseAll(fig, hStatus)
    ud = fig.UserData;

    % Stop acquisition timers
    stopTimers(ud);

    % Close cbmex
    try; cbmex('trialconfig', 0); catch; end
    try; cbmex('close');          catch; end

    % Close log file handles before clearing globals
    global fhComments fhTrials
    if ~isempty(fhComments) && fhComments > 0; fclose(fhComments); fhComments = []; end
    if ~isempty(fhTrials)   && fhTrials   > 0; fclose(fhTrials);   fhTrials   = []; end

    % Clear globals
    global trials inTrial
    trials  = struct([]);
    inTrial = false;

    % Clear persistent variables in all pipeline functions
    clear getJivesData
    clear jivesAnalysisSwitchyard
    clear plotJivesDashboard
    clear plotJivesPsychometrics
    clear plotJivesFixation
    clear plotJivesVisualSaccade
    clear plotJivesReceptiveField

    ud.T1      = [];
    ud.T2      = [];
    ud.running = false;
    fig.UserData = ud;

    % Re-enable Start and reset task field
    ud.startBtn.Enable  = 'on';
    ud.hTask.Value      = 'Waiting for task info...';
    ud.hTask.FontColor  = [0.4 0.4 0.4];

    hStatus.Text      = 'Stopped';
    hStatus.FontColor = [0.7 0.1 0.1];

    fprintf('All connections closed and state cleared.\n');
end

%% =========================================================================

function onCloseWindow(fig)
    ud = fig.UserData;
    % Stop UI timer
    if ~isempty(ud.T_ui) && isvalid(ud.T_ui)
        stop(ud.T_ui); delete(ud.T_ui);
    end
    % Stop acquisition if still running
    if ud.running
        stopTimers(ud);
        try; cbmex('trialconfig', 0); catch; end
        try; cbmex('close');          catch; end
        global fhComments fhTrials
        if ~isempty(fhComments) && fhComments > 0; fclose(fhComments); fhComments = []; end
        if ~isempty(fhTrials)   && fhTrials   > 0; fclose(fhTrials);   fhTrials   = []; end
    end
    delete(fig);
end

%% =========================================================================

function updateLabels(fig, hStatus, hTrials, hTask)
    global trials
    ud = fig.UserData;
    if ~isvalid(fig); return; end

    if ud.running
        hStatus.Text      = 'Running';
        hStatus.FontColor = [0.17 0.51 0.10];
    end

    if ~isempty(trials) && isstruct(trials)
        hTrials.Text = num2str(numel(trials));

        % Update task field from most recent trial
        taskStr = trials(end).Task;
        if ~isempty(taskStr) && ~strcmp(hTask.Value, taskStr)
            hTask.Value     = taskStr;
            hTask.FontColor = [0 0 0];
        end
    else
        hTrials.Text = '0';
    end
end

%% =========================================================================

function stopTimers(ud)
    for fn = {'T1', 'T2'}
        t = ud.(fn{1});
        if ~isempty(t) && isvalid(t)
            stop(t); delete(t);
        end
    end
end

%% =========================================================================

function onBrowse(fig)
    folder = uigetdir(fig.UserData.hExportPath.Value, 'Select export folder');
    if folder ~= 0
        fig.UserData.hExportPath.Value = folder;
    end
end

%% =========================================================================

function bp = readBasePathFile()
% Read the base export path from path.txt located next to this GUI file.
% Returns the first non-empty, non-comment (#) line trimmed, or '' if none.
    bp = '';
    thisDir  = fileparts(mfilename('fullpath'));
    pathFile = fullfile(thisDir, 'path.txt');
    if ~isfile(pathFile); return; end
    lines = strsplit(fileread(pathFile), {'\r\n', '\n', '\r'});
    lines = strtrim(lines);
    lines = lines(~cellfun(@isempty, lines));    % drop blank lines
    lines = lines(~startsWith(lines, '#'));      % drop comment lines
    if ~isempty(lines); bp = lines{1}; end
end
