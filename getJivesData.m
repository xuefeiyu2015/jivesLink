function outputData = getJivesData()
% getJivesData  T1 acquisition callback for jivesBROnline.
%
% Flushes the cbmex comment buffer every 250 ms, parses Jives comments in
% "Trial N: <event>" format. Returns a completed trial struct when a trial
% ends, or [] if no trial completed this tick.
%
% Trial parsing is adapted from doc/CommentTrialStructure.m.
% Called by jivesBROnline.m — do not call directly.

global inTrial
persistent localData

outputData = [];

dbstop if error

% Trial struct template — fields needed for online plots
% Extended here rather than in the entry script to keep jivesBROnline clean.
TEMPLATE = struct( ...
    'Trial_number',          NaN, ...
    'Task',        '',... % string: 'Fixation task', 'Visual Saccade Task', etc.
    'Trial_type',          '', ...   %string： visual or memory 
    'Start',              NaN, ...   % absolute time (s)
    'End',                NaN, ...   % absolute time (s)
    'Trialoutcome',       NaN, ...   % string: 'Correct', 'Time out', etc.
    'Choiceoutcome',      NaN, ...   % string: 'Correct choice', 'Wrong choice', 'No choice'
    'Choosen_choice',     NaN, ...   % string: '1' or '2'
    'Choicetime',         NaN, ...   % absolute time of target acquisition (s)
    'Target_1_presented', NaN, ...   % absolute time targets came on (s)
    'Target_2_presented', NaN, ...   % absolute time targets came on (s)
    'Target_1_position',  [NaN NaN], ...  % [x, y] deg
    'Target_2_position',  [NaN NaN]  ...  % [x, y] deg
);

% Flush both buffers every tick
%spikedata = cbmex('trialdata', 1);                        % keep spike buffer clear 
[cmts, ts, ~, ~] = cbmex('trialcomment', 1);  % flush comment buffer
if isempty(cmts); return; end


for i = 1:numel(cmts)
    tok = regexp(cmts{i}, '^Trial\s+(\d+):\s*(.*)$', 'tokens');
    if isempty(tok); continue; end   % skip "Experiment start/end: ..." lines

    trl_num    = str2double(tok{1}{1});
    event_text = strtrim(tok{1}{2});
    t          = ts(i);

    %First check whether the trial number changed or not
    if exist('localData','var') && ~isempty(localData) && trl_num ~= localData.Trial_number
        % Trial number changed — this means the previous trial ended without an "End - ..." comment
        % Store the previous trial if it has a valid start time
        if ~isnan(localData.Start)
            outputData = localData;
            fprintf('Trial %3d  outcome: %-12s  choice: %s\n', ...
                localData.Trial_number, num2str(localData.Trialoutcome), num2str(localData.Choosen_choice));
            disp('Incompelete trial ended without "End - ..." comment. Storing with whatever data we have.');
        end
        inTrial   = false;
        localData = []; 
        
    end

    % --- Trial start ---
    if contains(event_text, 'Start')
        inTrial             = true;
        localData           = TEMPLATE;
        localData.Trial_number = trl_num;
        localData.Start     = t;

    elseif ~inTrial
        continue   % ignore events outside a trial

    % --- Task type: "Task Time discrimination task", etc. ---
    elseif contains(event_text, 'Experiment')
        if isempty(localData.Task)
            localData.Task = strtrim(event_text(11:end));  % strip leading "Experiment"
        end
    elseif contains(event_text, 'Trial type')
        if isempty(localData.Trial_type)
            localData.Trial_type = strtrim(event_text(11:end));  % strip leading "Trial type"
        end

    
    % --- Choice: "Correct choice - 1", "Wrong choice - 2" ---
    elseif contains(event_text, '-') && contains(event_text, 'choice')
        dash = strfind(event_text, '-');
        if isnan(localData.Choosen_choice)
            localData.Choosen_choice = strtrim(event_text(dash+1:end));  % 1 or 2
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
    elseif contains(event_text, 'Target 1 acquired') || contains(event_text, 'Target 2 acquired')
        if isnan(localData.Choicetime)
            localData.Choicetime = t;
        end

    % --- Targets on ---
    elseif contains(event_text, 'Target 1 presented')
        if isnan(localData.Target_1_presented)
            localData.Target_1_presented = t;
        end
    elseif contains(event_text, 'Target 2 presented')
        if isnan(localData.Target_2_presented)
            localData.Target_2_presented = t;
        end

    % --- Target positions: "Target 1 position (x, y) deg" ---
    elseif contains(event_text, 'Target 1 position') || contains(event_text, 'Target 2 position')
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

    % --- Trial end: "End - Correct", "End - Time out", etc. ---
    elseif contains(event_text, 'End')
        dash = strfind(event_text, '-');
        if ~isempty(dash)
            localData.Trialoutcome = strtrim(event_text(dash+1:end));
        end
        localData.End = t;
        outputData = localData;
        fprintf('Trial %3d  outcome: %-12s  choice: %s\n', ...
            trl_num, num2str(localData.Trialoutcome), num2str(localData.Choosen_choice));
        inTrial   = false;
        localData = [];
    end
    
end


end
