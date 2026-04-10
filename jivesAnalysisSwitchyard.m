function jivesAnalysisSwitchyard(data)
% jivesAnalysisSwitchyard  T2 dispatch — selects analysis based on task type.
%
% Receives the latest completed trial struct from the base workspace (via
% the T2 string callback). Appends new trials to global `trials`, then
% dispatches to the task-specific plot based on the most recent task type:
%
%   Fixation task            -> plotJivesFixation(nFig)
%   Visual Saccade Task      -> plotJivesVisualSaccade(nFig)
%   Time discrimination task -> plotJivesPsychometrics(nFig)
%
% Called by T2 timer every 1 s. Do not call directly.

global trials
persistent lastTrialNum

% Append new trial if one arrived since last tick
if ~isempty(data) && (isempty(lastTrialNum) || data.Trial_number ~= lastTrialNum)
    lastTrialNum = data.Trial_number;
    if isempty(trials)
        trials = data;
    else
        trials(end+1) = data;
    end
end

if isempty(trials)
    return
end

% Session dashboard — always updated regardless of task type
plotJivesDashboard(1);

% Find most recent trial that has a task_type set
task_type = '';
for k = numel(trials):-1:1
    if ischar(trials(k).task_type) && ~isempty(trials(k).task_type)
        task_type = trials(k).task_type;
        break
    end
end

if isempty(task_type)
    return
end

switch task_type
    case 'Fixation task'
        plotJivesFixation(nFig);

    case 'Visual Saccade Task'
        plotJivesVisualSaccade(nFig);

    case 'Time discrimination task'
        plotJivesPsychometrics(nFig);

    otherwise
        fprintf('[Switchyard] Unknown task type: "%s"\n', task_type);
end
