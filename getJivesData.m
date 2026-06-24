function getJivesData()
% getJivesData  T1 acquisition callback for jivesBROnline.
%
% Flushes the cbmex comment buffer every 250 ms, parses Jives comments in
% "Trial N: <event>" format. Appends each completed trial directly to the
% global `trials` array (REVISED: replaces single-trial outputData return,
% so all trials in a buffer flush are captured even if multiple complete
% within one T1 tick).
%
% Trial parsing is adapted from doc/CommentTrialStructure.m.
% Called by jivesBROnline.m — do not call directly.

global inTrial trials fhComments fhTrials
persistent localData spikeBuf   % spikeBuf: rolling per-(ch,unit) spike-timestamp cell

dbstop if error

% Trial struct template — fields needed for online plots
% Extended here rather than in the entry script to keep jivesBROnline clean.
TEMPLATE = struct( ...
    'Trial_number',          NaN, ...
    'Task',        '',... % string: 'Fixation task', 'Visual Saccade Task', etc.
    'Trial_type',          '', ...   %string： visual or memory 
    'Start',              NaN, ...   % absolute time (s)
    'End',                NaN, ...   % absolute time (s)
    'Trialoutcome',       NaN, ...   % string: 'correct', 'timeout','brokefix' etc.
    'Choiceoutcome',      NaN, ...   % string: 'Correct choice', 'Wrong choice', 'No choice'
    'Choosen_choice',     NaN, ...   % numeric: 1 or 2 or NaN
    'Choicetime',         NaN, ...   % absolute time of target acquisition (s)
    'Target_1_presented', NaN, ...   % absolute time targets came on (s)
    'Target_2_presented', NaN, ...   % absolute time targets came on (s)
    'Target_1_position',  [NaN NaN], ...  % [x, y] deg
    'Target_2_position',  [NaN NaN],  ...  % [x, y] deg
    'Requested_target_2_time_offset', NaN,...  %time onset offset for time delay task
    'Fixation_point_off', NaN,... %time of fixation point of i.e. go cue
    'Fixation_exited', NaN,... %time of eyes exit the fixation window
    'spike_times', {{}}...        % {nCh x nUnitCols} cell of absolute spike timestamps within [Start, End]
);

% Flush both buffers every tick
spikedata = cbmex('trialdata', 1);                        % keep spike buffer clear
% first need to find out all channels start with chan**
% first column is the channel name
% --- accumulate sorted-unit spikes into rolling buffer (cols 1-2 = unsorted/hash, skip) ---
if ~isempty(spikedata)
    [nCh, nU] = size(spikedata);
    if isempty(spikeBuf) || ~isequal(size(spikeBuf), [nCh nU])
        spikeBuf = cell(nCh, nU);
    end
    for c = 1:nCh
        for u = 2:nU
            ts_new = spikedata{c, u};
            if ~isempty(ts_new)
                spikeBuf{c, u} = [spikeBuf{c, u}; ts_new(:)];
            end
        end
    end
end
[cmts, ts, ~, ~] = cbmex('trialcomment', 1);  % flush comment buffer

% Stream raw comments to log file
if ~isempty(fhComments) && fhComments > 0 && ~isempty(cmts)
    for k = 1:numel(cmts)
        fprintf(fhComments, '%.6f\t%s\n', ts(k), cmts{k}(1:92));
    end
end

%Strean raw spike for channel 1 

%{
if isempty(cmts); return; end
A=table(cmts);
A.t =ts;
A
%}
%try
for i = 1:numel(cmts)
    tok = regexp(cmts{i}(1:92), '^Trial\s+(\d+):\s*(.*)$', 'tokens');
    if isempty(tok); continue; end   % skip "Experiment start/end: ..." lines

    trl_num    = str2double(tok{1}{1});
    event_part = strsplit(tok{1}{2});
    event_text = strjoin(event_part(1:end-1),' ');
    t          = ts(i);
  %  disp(event_text);

    %First check whether the trial number changed or not
    if exist('localData','var') && ~isempty(localData) 
        % Trial number changed — this means the previous trial ended without an "End - ..." comment
        % remove the trial
        %{
        if ~isnan(localData.Start)
            outputData = localData;
            fprintf('Trial %3d  outcome: %-12s  choice: %s\n', ...
                localData.Trial_number, num2str(localData.Trialoutcome), num2str(localData.Choosen_choice));
            disp('Incompelete trial ended without "End - ..." comment. Storing with whatever data we have.');
        end
        %}
        if  trl_num ~= localData.Trial_number
            inTrial   = false;
            localData = [];
            spikeBuf  = {};   % drop stale partial-trial spike accumulator
        end

    end

    % --- Trial start ---
    if inTrial==false && contains(event_text, 'Start')
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
            tmp =  strtrim(event_text(dash(1)+1:end));%target_1 or target_2
            if contains(tmp,'1')
                localData.Choosen_choice = 1;
            elseif contains(tmp,'2')
                localData.Choosen_choice = 2;
            else
                 localData.Choosen_choice = NaN;
            end
        end
        if isnan(localData.Choiceoutcome)
            localData.Choiceoutcome = strtrim(event_text(1:dash(1)-1));     % 'Correct choice' etc.
        end

    % --- Outcome without number: "No choice" ---
    elseif ismember(event_text, {'Correct choice','Wrong choice','No choice'})
        if isnan(localData.Choiceoutcome)
            localData.Choiceoutcome = event_text;
        end
%
    % --- Choice time: target acquired ---
    elseif contains(event_text, 'Target 1 acquired') || contains(event_text, 'Target 2 acquired')
        if isnan(localData.Choicetime)
            localData.Choicetime = t;
        end
%}
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
            '^Target\s+(\d)\s+position\s*\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)\s*deg.*', ...
            'tokens');
        if ~isempty(coord_tok)
            tgt_n = str2double(coord_tok{1}{1});
            xy    = [str2double(coord_tok{1}{2}), str2double(coord_tok{1}{3})];
            field = sprintf('Target_%d_position', tgt_n);
            if all(isnan(localData.(field)))
                localData.(field) = xy;
            end
        end
     %For time onset delay
     elseif contains(event_text, 'Requested target 2 time offset')
        if isnan(localData.Requested_target_2_time_offset)
            time_pattern = '^(.*?)\s+([-+]?\d*\.?\d+)\s*ms.*';
            tokens = regexp(event_text, time_pattern, 'tokens');
            dur = str2double(tokens{1}{2});
            localData.Requested_target_2_time_offset = dur;
        end
     %For fixation off
    elseif contains(event_text,'Fixation point off','IgnoreCase',true)
        if isnan(localData.Fixation_point_off)
            localData.Fixation_point_off = t;
        end

    %For exiting fixation window
    elseif contains(event_text,'Fixation exited','IgnoreCase',true)
        if isnan(localData.Fixation_exited)
            localData.Fixation_exited = t;
        end

    % --- Trial end: "End - Correct", "End - Time out", etc. ---
    elseif contains(event_text, 'End')
        dash = strfind(event_text, '-');
        if ~isempty(dash)
            localData.Trialoutcome = strtrim(event_text(dash(1)+1:end));
        end
        localData.End = t;
        % --- slice spike buffer to this trial's window; trim past spikes ---
        if ~isempty(spikeBuf)
            localData.spike_times = cell(size(spikeBuf));
            for c = 1:size(spikeBuf,1)
                for u = 3:size(spikeBuf,2)
                    ts_all = spikeBuf{c, u};
                    if ~isempty(ts_all)
                        mask = ts_all >= localData.Start & ts_all <= localData.End;
                        localData.spike_times{c, u} = ts_all(mask);
                        spikeBuf{c, u} = ts_all(ts_all > localData.End);
                    end
                end
            end
        end
        % REVISED: append directly to global trials instead of returning a
        % single outputData — prevents trial loss when >1 trial completes
        % within the same 250 ms cbmex buffer flush.
        if isempty(trials)
            trials = localData;
        else
            %{
            if localData.Choicetime < localData.Fixation_point_off
                keyboard
            end
            %}
            trials(end+1) = localData;
        end

        % Stream completed trial to CSV log file
        if ~isempty(fhTrials) && fhTrials > 0
            fprintf(fhTrials, '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
                fmtVal(localData.Trial_number), ...
                fmtVal(localData.Task), ...
                fmtVal(localData.Trial_type), ...
                fmtVal(localData.Start), ...
                fmtVal(localData.End), ...
                fmtVal(localData.Trialoutcome), ...
                fmtVal(localData.Choiceoutcome), ...
                fmtVal(localData.Choosen_choice), ...
                fmtVal(localData.Choicetime), ...
                fmtVal(localData.Target_1_presented), ...
                fmtVal(localData.Target_2_presented), ...
                fmtVal(localData.Target_1_position(1)), ...
                fmtVal(localData.Target_1_position(2)), ...
                fmtVal(localData.Target_2_position(1)), ...
                fmtVal(localData.Target_2_position(2)), ...
                fmtVal(localData.Requested_target_2_time_offset), ...
                fmtVal(localData.Fixation_exited), ...
                fmtVal(localData.Fixation_point_off));
        end

        %
        fprintf('Trial %3d  outcome: %-12s  choice: %s\n', ...
            trl_num, num2str(localData.Trialoutcome), num2str(localData.Choosen_choice));
        %}
        inTrial   = false;
        localData = [];
    end
    
end
%{
catch
    keyboard
end
%}
end

function s = fmtVal(v)
% Convert a struct field value (numeric scalar or string) to a CSV token.
if ischar(v) || isstring(v)
    s = char(v);
elseif isnumeric(v) && isscalar(v) && ~isnan(v)
    if v == floor(v) && abs(v) < 1e9
        s = sprintf('%d', v);
    else
        s = sprintf('%.6f', v);
    end
else
    s = '';
end
end
