function plotJivesDashboard(nFig)
% plotJivesDashboard  Session-wide overview, updated every T2 tick (1 s).
%
% Four line plots — running proportion relative to total trials in buffer:
%   (1,1) Successful trials
%   (1,2) Break fixation trials
%   (2,1) Time out trials
%   (2,2) Rightward choices (Time discrimination task only)
%
% Called by jivesAnalysisSwitchyard every 1 s. Do not call directly.

global trials
if isempty(trials); return; end

n_total = numel(trials);

%% Build per-trial outcome vectors
is_success  = false(1, n_total);
is_breakfix = false(1, n_total);
is_timeout  = false(1, n_total);

td_choice_trial = false(1, n_total);  % time discrim trial with valid choice
td_is_right     = false(1, n_total);

for k = 1:n_total
    t = trials(k);

    % Outcome category
    if ~(isnumeric(t.Trialoutcome) && isnan(t.Trialoutcome))
        oc = lower(t.Trialoutcome);
        if contains(oc, 'break') || contains(oc, 'fixat')
            is_breakfix(k) = true;
        elseif contains(oc, 'time')
            is_timeout(k)  = true;
        else
            is_success(k)  = true;
        end
    end

    % Rightward choice — Time discrimination only
    if ~ischar(t.task_type) || ~strcmp(t.task_type, 'Time discrimination task')
        continue
    end
    if isnumeric(t.Choosen_choice) || isempty(t.Choosen_choice)
        continue
    end
    chosen_n = str2double(t.Choosen_choice);
    pos_x = trials(k).(['Target_' num2str(chosen_n) '_position'])(1);
    if isnan(pos_x); continue; end

    td_choice_trial(k) = true;
    td_is_right(k)     = pos_x > 0;
end

%% Running proportions (each element k = proportion through trial k)
x_all = 1:n_total;
prop_success  = cumsum(is_success)  ./ x_all;
prop_breakfix = cumsum(is_breakfix) ./ x_all;
prop_timeout  = cumsum(is_timeout)  ./ x_all;

td_idx  = find(td_choice_trial);           % trial indices with TD choices
n_td    = numel(td_idx);
if n_td > 0
    prop_right = cumsum(td_is_right(td_idx)) ./ (1:n_td);
end

%% Plot
figure(nFig);

subplot(2, 2, 1);
plot(x_all, prop_success * 100, 'g-', 'LineWidth', 1.2);
ylim([0 100]);  xlabel('Trial');  ylabel('%');
title(sprintf('Successful  (%.0f%%)', prop_success(end)*100));

subplot(2, 2, 2);
plot(x_all, prop_breakfix * 100, 'r-', 'LineWidth', 1.2);
ylim([0 100]);  xlabel('Trial');  ylabel('%');
title(sprintf('Break fixation  (%.0f%%)', prop_breakfix(end)*100));

subplot(2, 2, 3);
plot(x_all, prop_timeout * 100, 'm-', 'LineWidth', 1.2);
ylim([0 100]);  xlabel('Trial');  ylabel('%');
title(sprintf('Time out  (%.0f%%)', prop_timeout(end)*100));

subplot(2, 2, 4);
if n_td > 0
    plot(td_idx, prop_right * 100, 'b-', 'LineWidth', 1.2);
    hold on;  yline(50, '--k');  hold off;
    ylim([0 100]);  xlabel('Trial');  ylabel('%');
    title(sprintf('Rightward choices  (%.0f%%, N=%d)', prop_right(end)*100, n_td));
else
    cla;
    text(0.5, 0.5, 'No time discrimination trials yet', ...
        'HorizontalAlignment', 'center', 'Units', 'normalized', 'Color', [0.5 0.5 0.5]);
    title('Rightward choices');
end

sgtitle(sprintf('Session dashboard  —  %d trials total', n_total));
