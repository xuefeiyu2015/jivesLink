function plotJivesPsychometrics(nFig)
% plotJivesPsychometrics  T2 plotting callback for jivesBROnline.
%
% Reads the global `trials` struct array (populated by getJivesData) and
% updates a 6-panel psychometric figure:
%
%   1. Running P(choose T1)          4. Target positions (last 50 trials)
%   2. Psychometric function          5. Reaction time distribution
%   3. Overall choice proportions     6. Trial outcome breakdown
%
% Called by jivesBROnline.m — do not call directly.

global trials

if isempty(trials) || numel(trials) < 2; return; end

% --- Trials with a valid choice ---
valid  = ~cellfun(@(x) isequal(x, NaN), {trials.Choosen_choice});
tValid = trials(valid);
if numel(tValid) < 2; return; end

% Numeric choice (1 or 2)
chooseN = cellfun(@(s) str2double(s), {tValid.Choosen_choice});

% Target angles: right = positive, left = negative
T1xy = vertcat(tValid.Target_1_position);
T2xy = vertcat(tValid.Target_2_position);
[th1, ~] = cart2pol(T1xy(:,1), T1xy(:,2));
T1ang = mod(90 - rad2deg(th1), 360);
T1ang(T1ang >= 180) = T1ang(T1ang >= 180) - 360;   % −180..180

% Reaction time (ms)
hasRT = ~isnan([tValid.Choicetime]) & ~isnan([tValid.Target_1_presented]);
RT    = ([tValid.Choicetime] - [tValid.Target_1_presented]) * 1000;

% Outcome counts
outcomes    = {tValid.Trialoutcome};
outcomeList = {'Correct','Time out','Broke fixation'};
outCount    = cellfun(@(o) sum(strcmp(outcomes, o)), outcomeList);

%% --- Draw ---
figure(nFig); clf;
nRows = 2; nCols = 3;

% 1. Running P(choose T1)
subplot(nRows, nCols, 1); cla; hold on
window     = 20;
pT1running = movmean(chooseN == 1, min(window, numel(chooseN)));
plot(pT1running, 'LineWidth', 1.5)
yline(0.5, '--k')
ylim([0 1])
xlabel('Trial'); ylabel('P(choose T1)')
title(sprintf('Running P(T1)  [win=%d]', window))

% 2. Psychometric function: P(choose T1) by T1 angle
subplot(nRows, nCols, 2); cla; hold on
angs   = unique(T1ang);
pByAng = arrayfun(@(a) mean(chooseN(T1ang == a) == 1), angs);
nByAng = arrayfun(@(a) sum(T1ang == a), angs);
scatter(angs, pByAng, 30 + nByAng*3, 'filled')
plot(angs, pByAng, '-', 'Color', [0.5 0.5 0.5])
yline(0.5, '--k')
xlim([-180 180]); ylim([0 1])
xlabel('T1 angle (deg)'); ylabel('P(choose T1)')
title('Psychometric function')

% 3. Overall choice proportions
subplot(nRows, nCols, 3); cla
nT1 = sum(chooseN == 1);
nT2 = sum(chooseN == 2);
bar([nT1, nT2], 'FaceColor', [0.4 0.6 0.8])
set(gca, 'XTickLabel', {'Target 1','Target 2'})
ylabel('# choices')
title(sprintf('T1: %d (%.0f%%)   T2: %d (%.0f%%)', ...
    nT1, 100*nT1/(nT1+nT2), nT2, 100*nT2/(nT1+nT2)))

% 4. Target positions (last 50 trials), red = chosen
subplot(nRows, nCols, 4); cla; hold on; axis equal
n2plot = min(50, numel(tValid));
idx    = numel(tValid)-n2plot+1 : numel(tValid);
chN    = chooseN(idx);
scatter(T1xy(idx,1), T1xy(idx,2), 30, (chN==1)*[1 0 0] + (chN~=1)*[0 0 0], 'filled')
scatter(T2xy(idx,1), T2xy(idx,2), 30, (chN==2)*[1 0 0] + (chN~=2)*[0 0 0], 'filled')
plot([-20 20],[0 0],'k'); plot([0 0],[-20 20],'k')
xlabel('X (deg)'); ylabel('Y (deg)')
title(sprintf('Target locations (red = chosen, last %d)', n2plot))

% 5. Reaction time distribution
subplot(nRows, nCols, 5); cla
if sum(hasRT) > 3
    histogram(RT(hasRT), 20)
    xlabel('RT (ms)'); ylabel('# trials')
    title(sprintf('RT  median = %.0f ms', median(RT(hasRT))))
else
    axis off
    text(0.3, 0.5, 'Waiting for RT data...', 'Units','normalized')
end

% 6. Trial outcome breakdown
subplot(nRows, nCols, 6); cla
bar(outCount, 'FaceColor', [0.7 0.7 0.7])
set(gca, 'XTickLabel', outcomeList, 'XTickLabelRotation', 15)
ylabel('# trials')
title(sprintf('Total: %d trials', numel(trials)))

drawnow
