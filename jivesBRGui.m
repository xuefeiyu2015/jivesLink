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

fig.UserData = struct('T1', [], 'T2', [], 'T_ui', [], 'running', false, ...
                      'closing', false, 'starting', false);

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
hClose = uibutton(fig, 'push', ...
    'Position',       [190 155 150 50], ...
    'Text',           'Close All', ...
    'FontSize',       15, ...
    'FontWeight',     'bold', ...
    'BackgroundColor', [0.85 0.33 0.10], ...
    'ButtonPushedFcn', @(~,~) onCloseAll(fig, hStatus));
fig.UserData.closeBtn = hClose;   % stored so shutdownPipeline can disable it

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
chkSpikes = uicheckbox(fig, ...
    'Position', [20 36 320 22], ...
    'Text',     'Export spike time sample (.txt) — debug only', ...
    'Value',    false);

fig.UserData.hExportPath = hExportPath;
fig.UserData.chkComments = chkComments;
fig.UserData.chkTrials   = chkTrials;
fig.UserData.chkSpikes   = chkSpikes;

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
    if ud.running || ud.starting || ud.closing
        return   % re-entrancy guard: ignore repeat presses while busy
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

    % Mark busy and give immediate feedback — cbmex('open') blocks for
    % seconds and without this the window just freezes with no explanation.
    ud.starting = true;
    fig.UserData = ud;
    hStart.Enable     = 'off';
    hStatus.Text      = 'Connecting...';
    hStatus.FontColor = [0.85 0.55 0.10];
    drawnow limitrate nocallbacks

    % Reset globals
    global trials inTrial fhComments fhTrials fhSpikes
    trials  = struct([]);
    inTrial = false;

    % Connect cbmex BEFORE opening any log files, so a failed connect cannot
    % leak file handles or leave empty files on disk.
    try
        cbmexConnect(200);   % also pings the NSP: fails if Central is not open
    catch ME
        ud.starting = false;
        fig.UserData = ud;
        hStart.Enable     = 'on';
        hStatus.Text      = 'Stopped';
        hStatus.FontColor = [0.7 0.1 0.1];
        uialert(fig, ME.message, 'Central not ready');
        return
    end

    % Open streaming log files for this session (conditional on checkboxes)
    dtStr      = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    dateStr    = char(datetime('now', 'Format', 'yyyy-MM-dd'));   % date subfolder
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
    % Channel-1 unit-1/unit-2 spike timings (debug only; opt-in checkbox).
    if fig.UserData.chkSpikes.Value
        spikesDir = fullfile(exportPath, 'comments_online', dateStr);
        if ~isfolder(spikesDir); mkdir(spikesDir); end
        spikeFile = fullfile(spikesDir, ['spikes_ch1_' dtStr '.txt']);
        fhSpikes  = fopen(spikeFile, 'w');
        fprintf('[Export] spikes   → %s\n', spikeFile);
    else
        fhSpikes = [];
    end
    if fig.UserData.chkTrials.Value
        trialsDir = fullfile(exportPath, 'trials_online', dateStr);
        if ~isfolder(trialsDir); mkdir(trialsDir); end
        trialFile = fullfile(trialsDir, ['trials_' dtStr '.csv']);
        fhTrials  = fopen(trialFile, 'w');
        % 18 columns — must match the fprintf in getJivesData exactly. The
        % header previously omitted Fixation_exited, so the column labelled
        % Fixation_point_off actually carried Fixation_exited.
        fprintf(fhTrials, 'Trial_number,Task,Trial_type,Start,End,Trialoutcome,Choiceoutcome,Choosen_choice,Choicetime,Target_1_presented,Target_2_presented,Target_1_pos_x,Target_1_pos_y,Target_2_pos_x,Target_2_pos_y,Requested_target_2_time_offset,Fixation_exited,Fixation_point_off\n');
        fprintf('[Export] trials   → %s\n', trialFile);
    else
        fhTrials = [];
    end

    % REVISED: T1 calls getJivesData with no output — completed trials are
    % appended directly to global `trials` inside getJivesData.
    % ExecutionMode is 'fixedSpacing', NOT 'fixedRate'. Under fixedRate a
    % callback that overruns its period leaves MATLAB queueing the missed
    % executions cumulatively, so the timer never goes idle again — that is
    % exactly the saturation described in shutdownPipeline below, and it is
    % what made Close All hang. fixedSpacing waits Period AFTER the callback
    % returns, so an overrun self-limits instead of compounding.
    T1 = timer('Name', 'Jives_Acquire', 'Period', 0.25, 'ExecutionMode', 'fixedSpacing', ...
               'TimerFcn', 'getJivesData();', ...            % REVISED
               'ErrorFcn', @(~,e) onAcquireError(fig, e));

    % REVISED: T2 switchyard takes no argument — reads global `trials` directly.
    T2 = timer('Name', 'Jives_Plot', 'Period', 1.0, 'ExecutionMode', 'fixedSpacing', ...
               'TimerFcn', 'jivesAnalysisSwitchyard();', ... % REVISED
               'ErrorFcn', @(~,e) fprintf('[T2 error] %s\n', e.Data.message));

    start(T1);
    start(T2);

    ud.T1       = T1;
    ud.T2       = T2;
    ud.running  = true;
    ud.starting = false;
    fig.UserData = ud;

    hStart.Enable = 'off';
    hStatus.Text      = 'Running';
    hStatus.FontColor = [0.17 0.51 0.10];
end

%% =========================================================================

function onAcquireError(fig, e)
% T1 ErrorFcn. The timer has already stopped, so acquisition is dead until
% restart — say so in a pop-up instead of only on the command line.
    fprintf('[T1 error] %s\n', e.Data.message);
    if isvalid(fig)
        uialert(fig, sprintf(['Acquisition stopped:\n%s\n\n' ...
            'If Central was closed or the NSP disconnected, reopen Central, ' ...
            'then press Close All and Start again.'], e.Data.message), ...
            'Acquisition error');
    end
end

function onCloseAll(fig, hStatus)
    shutdownPipeline(fig, hStatus, true);
end

%% =========================================================================

function shutdownPipeline(fig, hStatus, restoreUI)
% Tear down the acquisition pipeline. Shared by the Close All button and the
% window CloseRequestFcn so both paths behave identically.
%
% WHY THE ORDER MATTERS
% The old version called stop() immediately followed by delete() on T1/T2,
% straight from the button callback. delete() on a timer whose TimerFcn is
% still executing BLOCKS — and T1 is a 0.25 s fixedRate timer whose callback
% (two cbmex reads, plus a growing `trials(end+1)` copy) can take longer than
% 0.25 s late in a session. Once that happens T1 saturates the callback queue
% and never goes idle, so delete(T1) waits forever. That is the freeze.
%
% The fix is: stop() first (no new callbacks queue), then drain with a hard
% time bound, then delete ONLY if the timer has actually gone idle. A timer
% that is still busy is left stopped and reaped asynchronously, so this
% function always returns and the GUI always comes back.

    ud = fig.UserData;
    if ud.closing
        return   % re-entrancy / double-click guard
    end
    ud.closing = true;
    fig.UserData = ud;

    % Immediate feedback, and lock out both buttons for the duration.
    if restoreUI
        hStatus.Text      = 'Stopping...';
        hStatus.FontColor = [0.85 0.55 0.10];
        if isfield(ud, 'closeBtn') && isvalid(ud.closeBtn); ud.closeBtn.Enable = 'off'; end
        if isfield(ud, 'startBtn') && isvalid(ud.startBtn); ud.startBtn.Enable = 'off'; end
        drawnow limitrate
    end

    % Whatever happens below, hand the GUI back in a usable state.
    if restoreUI
        guard = onCleanup(@() restoreAfterClose(fig, hStatus));
    end

    tAll = tic;

    % 1. Stop the UI refresh timer so it cannot fire mid-teardown.
    if ~isempty(ud.T_ui) && isvalid(ud.T_ui); stop(ud.T_ui); end

    % 2. Stop acquisition timers WITHOUT deleting them yet — this prevents any
    %    further callbacks from being queued.
    tTim = tic;
    for fn = {'T1', 'T2'}
        t = ud.(fn{1});
        if ~isempty(t) && isvalid(t); stop(t); end
    end

    % 3. Drain, with a hard time bound. drawnow (callbacks allowed) lets the
    %    in-flight callback finish and the queue flush.
    DRAIN_LIMIT = 3;                       % seconds
    tDrain = tic;
    while toc(tDrain) < DRAIN_LIMIT && anyTimerBusy(ud)
        drawnow limitrate
    end
    stillBusy = anyTimerBusy(ud);

    % 4. Delete ONLY timers that have actually gone idle — delete() on a busy
    %    timer blocks indefinitely, which is the bug being fixed. Anything
    %    still busy is left stopped and reaped asynchronously below.
    stale = {};
    for fn = {'T1', 'T2'}
        t = ud.(fn{1});
        if isempty(t) || ~isvalid(t); continue; end
        if strcmp(t.Running, 'off')
            delete(t);
        else
            stale{end+1} = t; %#ok<AGROW>
        end
    end
    if ~isempty(stale)
        fprintf(['[Close] WARNING: %d timer(s) still executing after %g s. Left ' ...
                 'stopped; will be reaped in the background. This means a T1/T2 ' ...
                 'callback is taking longer than its period.\n'], numel(stale), DRAIN_LIMIT);
        reaper = timer('Name','Jives_Reaper','StartDelay',5,'ExecutionMode','singleShot', ...
                       'TimerFcn', @(t,~) reapStaleTimers(stale, t));
        start(reaper);
    end
    tTimers = toc(tTim);

    % 5. Close cbmex. Skipped if a callback is still in flight — calling
    %    cbmex('close') underneath a live cbmex read can wedge the MEX.
    tCb = tic;
    if stillBusy
        fprintf('[Close] WARNING: skipping cbmex close — a callback is still in flight.\n');
        fprintf('[Close] Run CloseEverything.m once the warning above stops appearing.\n');
    else
        try; cbmex('trialconfig', 0); catch; end
        try; cbmex('close');          catch; end
    end
    tCbmex = toc(tCb);

    % 6. Close log file handles before clearing globals
    tF = tic;
    global fhComments fhTrials fhSpikes
    if ~isempty(fhComments) && fhComments > 0; fclose(fhComments); fhComments = []; end
    if ~isempty(fhTrials)   && fhTrials   > 0; fclose(fhTrials);   fhTrials   = []; end
    if ~isempty(fhSpikes)   && fhSpikes   > 0; fclose(fhSpikes);   fhSpikes   = []; end
    tFiles = toc(tF);

    % 7. Clear globals
    tC = tic;
    % `trials` and its companions must be cleared together — the plots rely on
    % tsum.n == numel(trials) == numel(spikeTrials), and leaving any of them
    % populated would carry data into the next session.
    global trials inTrial spikeTrials tsum spikeNCh spikeNUnits
    trials      = struct([]);
    inTrial     = false;
    spikeTrials = [];
    tsum        = [];
    spikeNCh    = [];
    spikeNUnits = [];

    % 8. Clear persistent variables in all pipeline functions. Safe here
    %    because none of these functions is on the call stack any more.
    clear getJivesData
    clear jivesAnalysisSwitchyard
    clear plotJivesDashboard
    clear plotJivesPsychometrics
    clear plotJivesFixation
    clear plotJivesVisualSaccade
    clear plotJivesReceptiveField
    tClear = toc(tC);

    ud = fig.UserData;
    ud.T1      = [];
    ud.T2      = [];
    ud.running = false;
    fig.UserData = ud;

    fprintf(['[Close] total %.2f s  (timers %.2f, cbmex %.2f, files %.2f, ' ...
             'clear %.2f) — all connections closed and state cleared.\n'], ...
            toc(tAll), tTimers, tCbmex, tFiles, tClear);
end

%% =========================================================================

function tf = anyTimerBusy(ud)
% True if T1 or T2 is still executing its TimerFcn.
    tf = false;
    for fn = {'T1', 'T2'}
        t = ud.(fn{1});
        if ~isempty(t) && isvalid(t) && strcmp(t.Running, 'on'); tf = true; return; end
    end
end

%% =========================================================================

function reapStaleTimers(stale, self)
% Delete timers that were still executing at shutdown, once they go idle.
% Reschedules itself rather than blocking, so it can never hang the session.
    remaining = {};
    for k = 1:numel(stale)
        t = stale{k};
        if ~isvalid(t); continue; end
        if strcmp(t.Running, 'off')
            delete(t);
        else
            remaining{end+1} = t; %#ok<AGROW>
        end
    end
    if isempty(remaining)
        fprintf('[Close] stale timers reaped.\n');
        delete(self);
    else
        next = timer('Name','Jives_Reaper','StartDelay',5,'ExecutionMode','singleShot', ...
                     'TimerFcn', @(t,~) reapStaleTimers(remaining, t));
        start(next);
        delete(self);
    end
end

%% =========================================================================

function restoreAfterClose(fig, hStatus)
% Return the GUI to the idle state. Runs via onCleanup so it executes even if
% shutdownPipeline errors partway through — a bad close must never leave the
% window wedged with both buttons disabled.
    if ~isvalid(fig); return; end
    ud = fig.UserData;
    ud.closing  = false;
    ud.running  = false;
    ud.starting = false;
    fig.UserData = ud;

    if isfield(ud, 'startBtn') && isvalid(ud.startBtn); ud.startBtn.Enable = 'on';  end
    if isfield(ud, 'closeBtn') && isvalid(ud.closeBtn); ud.closeBtn.Enable = 'on';  end
    if isfield(ud, 'hTask')    && isvalid(ud.hTask)
        ud.hTask.Value     = 'Waiting for task info...';
        ud.hTask.FontColor = [0.4 0.4 0.4];
    end
    if ~isempty(ud.T_ui) && isvalid(ud.T_ui) && strcmp(ud.T_ui.Running, 'off')
        start(ud.T_ui);   % resume label refresh for the next session
    end
    if isvalid(hStatus)
        hStatus.Text      = 'Stopped';
        hStatus.FontColor = [0.7 0.1 0.1];
    end
end

%% =========================================================================

function onCloseWindow(fig)
    ud = fig.UserData;
    % Tear down acquisition through the same path as the Close All button.
    % restoreUI = false: the window is going away, so there is nothing to
    % re-enable afterwards.
    if ud.running
        shutdownPipeline(fig, [], false);
    end
    % Stop UI timer last — it reads fig.UserData, so it must outlive the
    % teardown but not the figure.
    ud = fig.UserData;
    if ~isempty(ud.T_ui) && isvalid(ud.T_ui)
        stop(ud.T_ui); delete(ud.T_ui);
    end
    delete(fig);
end

%% =========================================================================

function updateLabels(fig, hStatus, hTrials, hTask)
    global trials
    % Validity check MUST come before touching UserData — this runs from a
    % timer, so the figure can be deleted between ticks.
    if ~isvalid(fig); return; end
    ud = fig.UserData;
    if ud.closing || ud.starting; return; end   % teardown/startup owns the labels

    if ud.running
        hStatus.Text      = 'Running';
        hStatus.FontColor = [0.17 0.51 0.10];
    end

    if ~isempty(trials) && isstruct(trials)
        hTrials.Text = num2str(numel(trials));

        % Update task field from most recent trial
        taskStr = trials(end).Task;
        if (ischar(taskStr) || isstring(taskStr)) && ~isempty(taskStr) && ...
                ~strcmp(hTask.Value, char(taskStr))
            hTask.Value     = char(taskStr);
            hTask.FontColor = [0 0 0];
        end
    else
        hTrials.Text = '0';
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
