function jivesBRGui()
% jivesBRGui  Minimal GUI for the Jives BR online pipeline.
%
%   Start     — opens cbmex, initialises globals, starts T1/T2
%   Close All — stops T1/T2, closes cbmex, clears globals and all
%               persistent variables in the pipeline functions

%% Build window
fig = uifigure('Name',     'Jives BR Online', ...
               'Position', [200 400 360 200], ...
               'Resize',   'off', ...
               'CloseRequestFcn', @(f,~) onCloseWindow(f));

fig.UserData = struct('T1', [], 'T2', [], 'T_ui', [], 'running', false);

%% Status row
uilabel(fig, 'Position', [20 162 55 20], 'Text', 'Status:');
hStatus = uilabel(fig, 'Position', [75 162 100 20], ...
    'Text', 'Stopped', 'FontColor', [0.7 0.1 0.1]);

uilabel(fig, 'Position', [190 162 45 20], 'Text', 'Trials:');
hTrials = uilabel(fig, 'Position', [238 162 80 20], 'Text', '0');

%% Task row
uilabel(fig, 'Position', [20 128 40 22], 'Text', 'Task:');
hTask = uieditfield(fig, 'text', ...
    'Position',  [62 128 278 22], ...
    'Value',     'Waiting for task info...', ...
    'Editable',  'off', ...
    'FontColor', [0.4 0.4 0.4]);

%% Buttons
hStart = uibutton(fig, 'push', ...
    'Position',       [20 50 150 50], ...
    'Text',           'Start', ...
    'FontSize',       15, ...
    'FontWeight',     'bold', ...
    'BackgroundColor', [0.47 0.67 0.19]);
hStart.ButtonPushedFcn = @(~,~) onStart(fig, hStart, hStatus);

fig.UserData.startBtn = hStart;   % store so onCloseAll can re-enable it
fig.UserData.hTask    = hTask;    % store so onCloseAll can reset it
uibutton(fig, 'push', ...
    'Position',       [190 50 150 50], ...
    'Text',           'Close All', ...
    'FontSize',       15, ...
    'FontWeight',     'bold', ...
    'BackgroundColor', [0.85 0.33 0.10], ...
    'ButtonPushedFcn', @(~,~) onCloseAll(fig, hStatus));

%% UI update timer — refreshes status, trial count, and task label every 0.5 s
T_ui = timer('Name', 'Jives_UI', 'Period', 0.5, 'ExecutionMode', 'fixedRate', ...
             'TimerFcn', @(~,~) updateLabels(fig, hStatus, hTrials, hTask));
fig.UserData.T_ui = T_ui;
start(T_ui);

end % jivesBRGui

%% =========================================================================

function onStart(fig, hStart, hStatus)
    ud = fig.UserData;
    if ud.running
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
    global trials inTrial
    trials  = struct([]);
    inTrial = false;

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
