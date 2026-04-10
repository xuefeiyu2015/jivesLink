function jivesBRGui()
% jivesBRGui  MATLAB GUI wrapper for the Jives BR online pipeline.
%
% Launching this function opens a control panel that:
%   - Opens cbmex and starts the dual-timer acquisition loop on Start
%   - Shows live trial count and connection status
%   - Lets the user enter an output folder and task label for saving figures
%   - Provides Refresh (force replot) and Save Figure buttons
%
% Calls getJivesData (T1, 250 ms) and plotJivesPsychometrics (T2, 1 s)
% without modifying those files. Psychometric figure is always figure 1.

nFig = 1;   % psychometric figure number

%% Build GUI window
fig = uifigure('Name',     'Jives BR Online', ...
               'Position', [200 400 480 260], ...
               'Resize',   'off', ...
               'CloseRequestFcn', @onClose);

% Store timer handles and nFig so callbacks can reach them
fig.UserData = struct('T1',[], 'T2',[], 'T_ui',[], 'nFig', nFig, 'running', false);

%% --- Output path row ---
uilabel(fig, 'Position',[20 210 90 22],  'Text','Output path');
hPath = uieditfield(fig, 'text', ...
    'Position',    [115 210 290 22], ...
    'Value',       pwd, ...
    'Placeholder', 'Folder for saved figures');
uibutton(fig, 'push', ...
    'Position',  [415 210 50 22], ...
    'Text',      'Browse', ...
    'ButtonPushedFcn', @(~,~) onBrowse(hPath));

%% --- Current task row ---
uilabel(fig, 'Position',[20 175 90 22],  'Text','Current task');
hTask = uieditfield(fig, 'text', ...
    'Position',    [115 175 350 22], ...
    'Placeholder', 'Task label used in saved filename');

%% --- Status row ---
uilabel(fig, 'Position',[20 75 60 20], 'Text','Status:');
hStatus = uilabel(fig, ...
    'Position',  [80 75 180 20], ...
    'Text',      'Stopped', ...
    'FontColor', [0.7 0.1 0.1]);

uilabel(fig, 'Position',[270 75 60 20], 'Text','Trials:');
hTrials = uilabel(fig, ...
    'Position',  [330 75 120 20], ...
    'Text',      '0');

%% --- Buttons row ---
hStart = uibutton(fig, 'push', ...
    'Position', [20  120 100 34], ...
    'Text',     'Start', ...
    'FontWeight','bold', ...
    'BackgroundColor', [0.47 0.67 0.19]);
hStart.ButtonPushedFcn = @(src,~) onStartStop(fig, src, hStatus);

uibutton(fig, 'push', ...
    'Position', [135 120 100 34], ...
    'Text',     'Refresh', ...
    'ButtonPushedFcn', @(~,~) onRefresh(fig));

uibutton(fig, 'push', ...
    'Position', [250 120 100 34], ...
    'Text',     'Save figure', ...
    'ButtonPushedFcn', @(~,~) onSave(fig, hPath, hTask));

%% --- Start UI update timer (reads globals, updates labels) ---
T_ui = timer('Name',          'Jives_UI', ...
             'Period',         0.5, ...
             'ExecutionMode', 'fixedRate', ...
             'TimerFcn',       @(~,~) updateLabels(hStatus, hTrials, fig));
fig.UserData.T_ui = T_ui;
start(T_ui);

end % jivesBRGui

%% =========================================================================
%% Button callbacks
%% =========================================================================

function onStartStop(fig, hStart, hStatus)
    ud = fig.UserData;

    if ~ud.running
        %% --- START ---
        global trials inTrial localData
        trials    = [];
        inTrial   = false;
        localData = [];

        try
            cbmex('open')
            cbmex('trialconfig', 1, 'double', 'absolute')
        catch ME
            uialert(fig, ME.message, 'cbmex error'); return
        end

        nFig = ud.nFig;
        ud.T1 = timer('Name','Jives_Acquire','Period',0.25,'ExecutionMode','fixedRate', ...
                      'TimerFcn', @(~,~) getJivesData(), ...
                      'ErrorFcn', @(~,e) fprintf('[T1 error] %s\n', e.Data.message));
        % Store initial period for adaptive timing
        ud.T1.UserData = struct('basePeriod', 0.25, 'lastProcessTime', 0, 'overloadCount', 0);
        ud.T2 = timer('Name','Jives_Plot',   'Period',1.0, 'ExecutionMode','fixedRate', ...
                      'TimerFcn', @(~,~) jivesAnalysisSwitchyard(nFig), ...
                      'ErrorFcn', @(~,e) fprintf('[T2 error] %s\n', e.Data.message));
        start(ud.T1);
        start(ud.T2);

        ud.running           = true;
        fig.UserData         = ud;
        hStart.Text          = 'Stop';
        hStart.BackgroundColor = [0.85 0.33 0.10];

    else
        %% --- STOP ---
        stopTimers(ud);
        try; cbmex('trialconfig', 0); catch; end
        try; cbmex('close');          catch; end

        ud.running           = false;
        ud.T1                = [];
        ud.T2                = [];
        fig.UserData         = ud;
        hStart.Text          = 'Start';
        hStart.BackgroundColor = [0.47 0.67 0.19];
    end
end

function onRefresh(fig)
    nFig = fig.UserData.nFig;
    try
        plotJivesPsychometrics(nFig);
    catch ME
        uialert(fig, ME.message, 'Refresh error');
    end
end

function onSave(fig, hPath, hTask)
    nFig    = fig.UserData.nFig;
    outDir  = strtrim(hPath.Value);
    task    = strtrim(hTask.Value);

    if isempty(outDir) || ~isfolder(outDir)
        uialert(fig, 'Output path does not exist. Enter a valid folder.', 'Save error');
        return
    end

    if isempty(task); task = 'jives'; end

    timestamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
    fname     = fullfile(outDir, [task '_' timestamp '.png']);

    try
        f = figure(nFig);
        exportgraphics(f, fname, 'Resolution', 150);
        fprintf('Figure saved: %s\n', fname);
    catch ME
        uialert(fig, ME.message, 'Save error');
    end
end

function onBrowse(hPath)
    folder = uigetdir(hPath.Value, 'Select output folder');
    if folder ~= 0
        hPath.Value = folder;
    end
end

%% =========================================================================
%% GUI close — stop all timers, close cbmex
%% =========================================================================

function onClose(fig, ~)
    ud = fig.UserData;

    % Stop UI update timer
    if ~isempty(ud.T_ui) && isvalid(ud.T_ui)
        stop(ud.T_ui); delete(ud.T_ui);
    end

    % Stop acquisition timers if running
    if ud.running
        stopTimers(ud);
        try; cbmex('trialconfig', 0); catch; end
        try; cbmex('close');          catch; end
    end

    delete(fig);
end

%% =========================================================================
%% Helpers
%% =========================================================================

function updateLabels(hStatus, hTrials, fig)
    global trials
    ud = fig.UserData;

    if ud.running
        hStatus.Text      = 'Running';
        hStatus.FontColor = [0.17 0.51 0.10];
    else
        hStatus.Text      = 'Stopped';
        hStatus.FontColor = [0.7  0.1  0.1];
    end

    if ~isempty(trials)
        hTrials.Text = num2str(numel(trials));
    else
        hTrials.Text = '0';
    end
end

function stopTimers(ud)
    for fn = {'T1','T2'}
        t = ud.(fn{1});
        if ~isempty(t) && isvalid(t)
            stop(t); delete(t);
        end
    end
end
