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

global inTrial trials spikeTrials tsum spikeNCh spikeNUnits fhComments fhTrials fhSpikes
persistent localData spikeBuf   % spikeBuf: rolling per-(ch,unit) spike-timestamp cell

% Companion globals to `trials`, all appended in the same block below so that
%   tsum.n == numel(trials) == numel(spikeTrials)
% holds at every point a plot function can observe them:
%   spikeTrials  struct array, one entry per trial, flat .ts/.ch/.unit arrays
%   tsum         preallocated numeric mirror of the fields the plots need
%   spikeNCh     channel count of the spike buffer  (sizes the RF dropdown)
%   spikeNUnits  unit-column count of the spike buffer

% NB: no `dbstop if error` here — this runs 4x/second, and re-arming error
% breakpoints every tick disables JIT acceleration session-wide and turns any
% shutdown error into a silent debugger halt inside a timer callback.

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
    'Fixation_exited', NaN...  %time of eyes exit the fixation window
);
% NB: spike timestamps deliberately do NOT live in this struct any more — they
% are appended to the parallel global `spikeTrials`. Keeping an nCh x nUnit
% cell grid here made every slice, copy or comma-list expansion of `trials`
% proportional to the channel count.

% Flush both buffers every tick
spikedata = cbmex('trialdata', 1);                        % keep spike buffer clear
% Keep only spike channels (rows whose name contains "chan", e.g.
% "Hub1-chan1") and drop the channel-name column, so every remaining column
% is unit spike data (col 1 = unsorted, col 2+ = sorted). Requires >=2
% columns (name + at least one unit); else there are no spikes this tick.
if ~isempty(spikedata) && size(spikedata, 2) >= 2
    isSpikeCh = cellfun(@(nm) (ischar(nm) || isstring(nm)) && ...
                              contains(string(nm), "chan", 'IgnoreCase', true), ...
                        spikedata(:,1));
    spikedata = spikedata(isSpikeCh, 2:end);   % drop name col; keep unit-timestamp cols
else
    spikedata = {};                            % no spike-unit columns this tick
end
% --- accumulate unit spikes into rolling buffer (all cols are units: col 1 = unsorted, col 2+ = sorted) ---
if ~isempty(spikedata)
    [nCh, nU] = size(spikedata);
    if isempty(spikeBuf) || ~isequal(size(spikeBuf), [nCh nU])
        spikeBuf = cell(nCh, nU);
    end
    % Buffer dimensions are the FULL channel/unit count regardless of which
    % channels happened to fire this tick. The RF dropdowns are sized from
    % these, so they must not be derived from the spikes actually present or
    % the channel list would shrink whenever activity is sparse.
    spikeNCh    = nCh;
    spikeNUnits = nU;
    % Touch only the cells carrying new spikes. The blanket nested loop cost
    % nCh*nU iterations 4x/second — 1024 of them at 256x4, nearly all no-ops.
    nz = find(~cellfun(@isempty, spikedata)).';
    for q = nz
        spikeBuf{q} = [spikeBuf{q}; spikedata{q}(:)];
    end
end
[cmts, ts, ~, ~] = cbmex('trialcomment', 1);  % flush comment buffer

% Stream raw comments to log file
if ~isempty(fhComments) && fhComments > 0 && ~isempty(cmts)
    for k = 1:numel(cmts)
        fprintf(fhComments, '%.6f\t%s\n', ts(k), cmts{k}(1:92));
    end
end

% Stream channel-1 unit-1 / unit-2 spike timestamps to log, as they arrive.
% Format: one spike per line "<timestamp_s>\t<unit>". spikedata rows are
% spike channels, cols are units (col 1 = unit 1 = unsorted, col 2 = unit 2).
if ~isempty(fhSpikes) && fhSpikes > 0 && ~isempty(spikedata) && size(spikedata,1) >= 1
    for u = 1:min(2, size(spikedata,2))
        tsu = spikedata{1, u}(:);
        if ~isempty(tsu)
            fprintf(fhSpikes, '%.6f\t%d\n', [tsu, repmat(u, numel(tsu), 1)].');
        end
    end
end

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
        % Flat columnar storage (ts / ch / unit) rather than an nCh x nUnit
        % cell grid. At 256 ch x 4 units the grid cost ~1024 mxArray headers
        % per trial (~100 kB) even when nearly every cell was empty, and that
        % overhead was paid again by every slice or copy of `trials`. Three
        % numeric arrays hold the same information and let the RF plot select
        % spikes with a logical mask instead of a per-unit cell loop.
        % chStart is an offset table: channel c occupies ts(chStart(c) :
        % chStart(c+1)-1). Without it, selecting a channel means a mask over
        % EVERY spike in the trial (~nCh*rate comparisons), which made the RF
        % channel-switch rebuild scale with channel count. With it, selecting
        % a channel is a contiguous slice, as cheap as the old cell index.
        nChBuf = size(spikeBuf, 1);
        spk = struct('ts',      zeros(0,1), ...
                     'ch',      zeros(0,1,'uint16'), ...
                     'unit',    zeros(0,1,'uint8'), ...
                     'chStart', ones(nChBuf+1, 1, 'uint32'));
        if ~isempty(spikeBuf)
            nz = find(~cellfun(@isempty, spikeBuf)).';
            if ~isempty(nz)
                [rIdx, cIdx] = ind2sub(size(spikeBuf), nz);
                % Typed empties so vertcat keeps the class even when a trial
                % has no spikes in window on some channels.
                tsC = repmat({zeros(0,1)},          numel(nz), 1);
                chC = repmat({zeros(0,1,'uint16')}, numel(nz), 1);
                unC = repmat({zeros(0,1,'uint8')},  numel(nz), 1);
                for q = 1:numel(nz)
                    ts_all = spikeBuf{nz(q)};
                    mask   = ts_all >= localData.Start & ts_all <= localData.End;
                    nsp    = sum(mask);
                    if nsp > 0
                        tsC{q} = ts_all(mask);
                        chC{q} = repmat(uint16(rIdx(q)), nsp, 1);
                        unC{q} = repmat(uint8(cIdx(q)),  nsp, 1);
                    end
                    spikeBuf{nz(q)} = ts_all(ts_all > localData.End);
                end
                spk.ts   = vertcat(tsC{:});
                spk.ch   = vertcat(chC{:});
                spk.unit = vertcat(unC{:});
                % Group by channel, and by time within each channel. A single
                % channel's spikes are then contiguous AND time-ordered, so a
                % slice needs no further sort even in "all units" mode.
                [~, ord] = sortrows([double(spk.ch), spk.ts]);
                spk.ts   = spk.ts(ord);
                spk.ch   = spk.ch(ord);
                spk.unit = spk.unit(ord);
                cnts        = accumarray(double(spk.ch), 1, [nChBuf 1]);
                spk.chStart = uint32([1; 1 + cumsum(cnts)]);
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
        if isempty(spikeTrials)
            spikeTrials = spk;
        else
            spikeTrials(end+1) = spk;
        end

        % --- numeric summary mirror -----------------------------------------
        % Every value the dashboard and the psychometric plot need, decoded
        % ONCE here, so neither has to scan the `trials` struct array on the
        % T2 tick. Appended in lockstep with `trials`/`spikeTrials` above.
        if isempty(tsum);      tsum = tsumInit(1000); end
        if tsum.n >= tsum.cap; tsum = tsumGrow(tsum);  end
        k = tsum.n + 1;
        tsum.trialNum(k)   = localData.Trial_number;
        tsum.outcome(k)    = outcomeMask(localData.Trialoutcome);
        tsum.isTimeTask(k) = contains(localData.Task, 'time');
        tsum.choice(k)     = localData.Choosen_choice;
        tsum.stimulus(k)   = localData.Requested_target_2_time_offset;
        tsum.direction(k)  = t1Direction(localData.Target_1_position);
        % NB: hasRT tests Fixation_point_off while RT is measured from
        % Fixation_exited. That asymmetry is reproduced exactly as
        % plotJivesPsychometrics computed it — not silently "fixed" here.
        tsum.hasRT(k)      = ~isnan(localData.Choicetime) && ...
                             ~isnan(localData.Fixation_point_off);
        tsum.RT(k)         = (localData.Choicetime - localData.Fixation_exited)/1000;
        tsum.n             = k;

        % Stream completed trial to CSV log file
        if ~isempty(fhTrials) && fhTrials > 0
            % 18 specifiers for 18 values. This previously had only 17: MATLAB
            % RECYCLES the format when arguments remain, so each trial wrote 17
            % fields + newline and then Fixation_point_off with no newline,
            % which ran into the next trial's row. Every row after the first
            % was shifted one column right, and the file ended mid-row.
            fprintf(fhTrials, '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
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

function tsum = tsumInit(cap)
% Preallocated numeric mirror of `trials`. Grown in chunks so appending a
% trial is amortised O(1) rather than reallocating the whole array.
tsum = struct( ...
    'n',          0, ...
    'cap',        cap, ...
    'trialNum',   nan(cap,1), ...
    'outcome',    zeros(cap,1,'uint8'), ...
    'isTimeTask', false(cap,1), ...
    'choice',     nan(cap,1), ...
    'stimulus',   nan(cap,1), ...
    'direction',  nan(cap,1), ...
    'RT',         nan(cap,1), ...
    'hasRT',      false(cap,1));
end


function tsum = tsumGrow(tsum)
% Double the capacity, preserving the values already stored.
pad = tsum.cap;
tsum.trialNum   = [tsum.trialNum;   nan(pad,1)];
tsum.outcome    = [tsum.outcome;    zeros(pad,1,'uint8')];
tsum.isTimeTask = [tsum.isTimeTask; false(pad,1)];
tsum.choice     = [tsum.choice;     nan(pad,1)];
tsum.stimulus   = [tsum.stimulus;   nan(pad,1)];
tsum.direction  = [tsum.direction;  nan(pad,1)];
tsum.RT         = [tsum.RT;         nan(pad,1)];
tsum.hasRT      = [tsum.hasRT;      false(pad,1)];
tsum.cap        = tsum.cap + pad;
end


function m = outcomeMask(s)
% Encode a Trialoutcome string as a bitmask:
%   bit 1 (1) = 'correct'   bit 2 (2) = 'broke'
%   bit 3 (4) = 'timeout'   bit 4 (8) = 'wrong'
% Kept as four INDEPENDENT bits rather than one exclusive code, so a string
% matching more than one term is counted in both — exactly as the four
% separate contains() tests in plotJivesDashboard behaved.
% Case-sensitive on purpose: Jives sends lowercase (see CLAUDE.md).
m = uint8(0);
if ~(ischar(s) || isstring(s)); return; end
s = char(s);
if contains(s, 'correct'); m = bitor(m, uint8(1)); end
if contains(s, 'broke');   m = bitor(m, uint8(2)); end
if contains(s, 'timeout'); m = bitor(m, uint8(4)); end
if contains(s, 'wrong');   m = bitor(m, uint8(8)); end
end


function d = t1Direction(xy)
% Sign of the target-1 direction: +1 = right, -1 = left, NaN if unknown.
% Mirrors the cart2pol -> compass-degrees conversion that
% plotJivesPsychometrics applied to Target_1_position.
if numel(xy) < 2 || any(isnan(xy(1:2)))
    d = NaN;
    return;
end
th  = cart2pol(xy(1), xy(2));
ang = mod(90 - rad2deg(th), 360);
if ang >= 180; ang = ang - 360; end     % wrap to -180..180
d = sign(ang);
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
