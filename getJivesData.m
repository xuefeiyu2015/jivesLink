function getJivesData()
% getJivesData  T1 acquisition callback for jivesBROnline.
%
% Flushes the cbmex comment buffer every 250 ms, parses Jives comments in
% "Trial N: <event>" format, and accumulates completed trials into the global
% `trials` struct array.
%
% Trial parsing is adapted from doc/CommentTrialStructure.m.
% Called by jivesBROnline.m — do not call directly.

global trials inTrial localData

% Trial struct template — fields needed for psychometrics.
% Extended here rather than in the entry script to keep jivesBROnline clean.
TEMPLATE = struct( ...
    'trial_num',          NaN, ...
    'Start',              NaN, ...   % absolute time (s)
    'End',                NaN, ...   % absolute time (s)
    'Trialoutcome',       NaN, ...   % string: 'Correct', 'Time out', etc.
    'Choiceoutcome',      NaN, ...   % string: 'Correct choice', 'Wrong choice', 'No choice'
    'Choosen_choice',     NaN, ...   % string: '1' or '2'
    'Choicetime',         NaN, ...   % absolute time of target acquisition (s)
    'Target_1_presented', NaN, ...   % absolute time targets came on (s)
    'Target_1_position',  [NaN NaN], ...  % [x, y] deg
    'Target_2_position',  [NaN NaN]  ...  % [x, y] deg
);

% Flush both buffers every tick
cbmex('trialdata', 1);                        % keep spike buffer clear (unused here)
[cmts, ts, ~, ~] = cbmex('trialcomment', 1);  % flush comment buffer
if isempty(cmts); return; end

% Sort by timestamp
[ts, ord] = sort(ts);
cmts = cmts(ord);

for i = 1:numel(cmts)
    tok = regexp(cmts{i}, '^Trial\s+(\d+):\s*(.*)$', 'tokens');
    if isempty(tok); continue; end   % skip "Experiment start/end: ..." lines

    trl_num    = str2double(tok{1}{1});
    event_text = strtrim(tok{1}{2});
    t          = ts(i);

    % --- Trial start ---
    if strcmp(event_text, 'Start')
        inTrial             = true;
        localData           = TEMPLATE;
        localData.trial_num = trl_num;
        localData.Start     = t;

    elseif ~inTrial
        continue   % ignore events outside a trial

    % --- Trial end: "End - Correct", "End - Time out", etc. ---
    elseif startsWith(event_text, 'End')
        dash = strfind(event_text, '-');
        if ~isempty(dash)
            localData.Trialoutcome = strtrim(event_text(dash+1:end));
        end
        localData.End = t;

        if isempty(trials)
            trials = localData;
        else
            trials(end+1) = localData; %#ok<AGROW>
        end
        fprintf('Trial %3d  outcome: %-12s  choice: %s\n', ...
            trl_num, num2str(localData.Trialoutcome), num2str(localData.Choosen_choice));
        inTrial   = false;
        localData = [];

    % --- Choice: "Correct choice - 1", "Wrong choice - 2" ---
    elseif contains(event_text, '-') && contains(event_text, 'choice')
        dash = strfind(event_text, '-');
        if isnan(localData.Choosen_choice)
            localData.Choosen_choice = strtrim(event_text(dash+1:end));  % '1' or '2'
        end
        if isnan(localData.Choiceoutcome)
            localData.Choiceoutcome = strtrim(event_text(1:dash-1));     % 'Correct choice' etc.
        end

    % --- Outcome without number: "No choice" ---
    elseif ismember(event_text, {'Correct choice','Wrong choice','No choice'})
        if isnan(localData.Choiceoutcome)
            localData.Choiceoutcome = event_text;
        end

    % --- Choice time: target acquired ---
    elseif strcmp(event_text, 'Target 1 acquired') || strcmp(event_text, 'Target 2 acquired')
        if isnan(localData.Choicetime)
            localData.Choicetime = t;
        end

    % --- Targets on ---
    elseif strcmp(event_text, 'Target 1 presented')
        if isnan(localData.Target_1_presented)
            localData.Target_1_presented = t;
        end

    % --- Target positions: "Target 1 position (x, y) deg" ---
    elseif startsWith(event_text, 'Target')
        coord_tok = regexp(event_text, ...
            '^Target\s+(\d)\s+position\s*\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)\s*deg$', ...
            'tokens');
        if ~isempty(coord_tok)
            tgt_n = str2double(coord_tok{1}{1});
            xy    = [str2double(coord_tok{1}{2}), str2double(coord_tok{1}{3})];
            field = sprintf('Target_%d_position', tgt_n);
            if all(isnan(localData.(field)))
                localData.(field) = xy;
            end
        end
    end
end
