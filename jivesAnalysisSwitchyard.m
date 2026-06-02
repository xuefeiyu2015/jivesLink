function jivesAnalysisSwitchyard()
% jivesAnalysisSwitchyard  T2 dispatch — selects analysis based on task type.
%
% Reads global `trials` (populated directly by getJivesData) and dispatches
% to the task-specific plot based on the most recent task type:
%
%   Fixation task            -> plotJivesFixation(nFig)
%   Visual Saccade Task      -> plotJivesVisualSaccade(nFig)
%   Time discrimination task -> plotJivesPsychometrics(nFig)
%
% REVISED: no longer receives `data` argument or appends to `trials` —
% getJivesData now appends directly, so all trials in a fast buffer flush
% are preserved. Switchyard only reads and dispatches.
%
% Called by T2 timer every 1 s. Do not call directly.
persistent lastTrialNum;
global trials;

if isempty(trials)
    return
end

% Skip if no new trial arrived since last T2 tick
if ~isempty(lastTrialNum) && trials(end).Trial_number == lastTrialNum
    return
end
lastTrialNum = trials(end).Trial_number;
    


% Session dashboard — always updated regardless of task type


% Find most recent trial that has a task_type set
task_type = trials(end).Task;

plotJivesDashboard(1);

%
if contains(task_type,'fixation')
   
       % plotJivesFixation(2);

elseif contains(task_type, 'saccade', 'IgnoreCase', true)
        plotJivesReceptiveField(5);

elseif contains(task_type, 'time')
        plotJivesPsychometrics(4);

else
        fprintf('[Switchyard] Unknown task type: "%s"\n', task_type);
end
%}