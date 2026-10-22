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
% Does NOT call drawnow — the switchyard issues a single flush per tick.
%
% Reads the numeric mirror `tsum` (built once per trial in getJivesData)
% rather than rescanning the `trials` struct array on every tick.
%
% Periods: the session is cut into periods by the Superimpose button. Pressing
% it freezes the current period's psychometric / RT points and fits on screen
% (static, in that period's color) and starts a new period, in the next color,
% from the next trial. Clear removes every period and restarts at color 1.
%
% Bias / Threshold: a sliding window of N_WIN valid trials of the current
% period, stepped by one trial. While the period has k < N_WIN trials the
% window grows (1..k); after that it is (k-N_WIN+1)..k. x = valid-trial count
% since the last Clear, so successive periods sit side by side.
%
% Stay toggle (default ON): when the session returns to this task after
% running another one, Stay ON keeps plotting on the same figure; Stay OFF
% freezes the old figure (left open, controls disabled) and opens a new one,
% figure nFig + 100*(block-1), holding only the trials from the return onward.

global tsum trials

N_WIN = 100;   % bias/threshold sliding-window length (valid trials)

if isempty(tsum) || tsum.n < 2; return; end

%try
 %initialization
persistent fig2 dhandle dlast bhandle thandle nFit time_count ax1 legH htot ...
           ax_rtL ax_rtR rtdot_L rtdot_R rtfit_L rtfit_R rtxt_L rtxt_R ...
           rtlast_L rtlast_R rtx_L rtx_R pPrev optz ...
           ax2 ax3 bhAll thAll frozenH pWin ...
           lastSeenN block stayDefault;
if isempty(block);       block = 1;          end
if isempty(stayDefault); stayDefault = true; end   % psychometric: Stay on by default
if ~isempty(fig2) && isvalid(fig2); stayDefault = fig2.UserData.stay; end

% --- Returned to this task after another one? (Stay off -> new figure) ---
% Only the trials since the last call are scanned; a trial with an empty
% Task (dropped comment) never counts as a switch.
newBlockOffset = [];
nNow = numel(trials);
if ~isempty(lastSeenN) && nNow > lastSeenN
    g = lastForeignTrial(trials, lastSeenN + 1, nNow, @(t) ~contains(t, 'time'));
    if ~isempty(g) && ~stayDefault
        if ~isempty(fig2) && isvalid(fig2)
            freezeFigure(fig2, sprintf('Psychometric — block %d (frozen)', block));
            block = block + 1;
        end
        fig2 = [];
        newBlockOffset = g;      % new figure starts at the first returning trial
    end
end
lastSeenN = nNow;

if isempty(fig2) || ~isvalid(fig2)
    fig2 = figure(nFig + 100*(block-1));
    fig2.Name = sprintf('Psychometric — block %d', block);
    fig2.UserData = struct('trialOffset', 0, 'doClear', false, ...
        'doSuperimpose', false, 'period', 1, 'xBase', 0, 'nDone', 0, ...
        'corrBase', 0, 'nCorrLive', 0, 'stay', stayDefault);
    c1 = periodColor(1);

    ax1 = subplot(4,2,[1,2,3,4],'Parent',fig2);
    hold(ax1, 'on');
    % scatter (not animatedline) so each dot's size can encode its trial count
    dhandle  = scatter(ax1, nan, nan, 36, c1, 'filled', 'DisplayName','Psychometric function');
    plot([0,0],[0,1],'--k');
    plot([-250,250],[0.5,0.5],'--k');

    nFit = animatedline('Color',c1,'LineStyle','-','LineWidth',2);

    % Black-edged ring marking the most recently updated stimulus level
    dlast = scatter(ax1, nan, nan, 36, c1, 'filled', ...
        'MarkerEdgeColor', [0 0 0], 'LineWidth', 2, 'DisplayName','Latest level');

    xlabel('Onset time delay(s)');

    ylim([0 1]);
    yticks([0,0.5,1]);
    xlim([-250,250]);
    ylabel('Proprotion');
    title('Psychometric function', 'FontSize', 15);

    % Segment legend (top-left, where P(right) ~ 0 leaves the axes empty):
    % one row per superimposed segment, each backed by an invisible proxy
    % line so a segment gets a row even if it never produced a valid fit.
    legH = segmentProxy(ax1, c1, segmentLabel(1, 0, 0, NaN, NaN, true));
    buildSegLegend(ax1, legH);

    % Running total over all segments since the last Clear (= sum of the
    % legend rows), gray, bottom-right — empty because P(right) ~ 1 there.
    htot = text(ax1, 0.98, 0.04, '', 'Units', 'normalized', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
        'FontName', 'FixedWidth', 'FontSize', 10, 'Color', [0.5 0.5 0.5]);

    ax2 = subplot(4,2,5,'Parent',fig2);
    box off
    title('Bias', 'FontSize', 15)
    xlabel(ax2, 'Trial number');
    ax3 = subplot(4,2,6,'Parent',fig2);
    box off
    title('Treshold', 'FontSize', 15);
    xlabel(ax3, 'Trial number');
    % One bias/threshold line per period; bhAll/thAll keep every period's line
    [bhandle, thandle] = newBiasLines(ax2, ax3, c1);
    bhAll = bhandle;  thAll = thandle;
    frozenH = gobjects(0);   % frozen-period objects + boundary lines (Clear deletes)

    % RT vs asynchrony — leftward onset first (stimulus_dir < 0)
    ax_rtL = subplot(4,2,7,'Parent',fig2);
    box off
    hold(ax_rtL, 'on');
    % scatter (not animatedline) so dot size can encode trials-per-level
    rtdot_L = scatter(ax_rtL, nan, nan, 36, c1, 'filled');               % leftward choice (congruent)
    rtfit_L = animatedline(ax_rtL,'Color',c1,'LineStyle','-','LineWidth',1.5);
    rtx_L   = scatter(ax_rtL, nan, nan, 36, c1, 'x', 'LineWidth', 1.8);  % rightward choice (cross)
    rtlast_L = scatter(ax_rtL, nan, nan, 36, 'MarkerEdgeColor',[0 0 0], ...
        'MarkerFaceColor','none', 'LineWidth', 2);     % hollow latest-trial ring
    xlabel(ax_rtL,'Onset asynchrony (ms)');
    ylabel(ax_rtL,'RT (s)');
    title(ax_rtL,'RT — Leftward onset first', 'FontSize', 15);
    rtxt_L  = text(ax_rtL, 0.98, 0.95, '', 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top','FontSize',10);

    % RT vs asynchrony — rightward onset first (stimulus_dir > 0)
    ax_rtR = subplot(4,2,8,'Parent',fig2);
    box off
    hold(ax_rtR, 'on');
    % scatter (not animatedline) so dot size can encode trials-per-level
    rtdot_R = scatter(ax_rtR, nan, nan, 36, c1, 'filled');               % rightward choice (congruent)
    rtfit_R = animatedline(ax_rtR,'Color',c1,'LineStyle','-','LineWidth',1.5);
    rtx_R   = scatter(ax_rtR, nan, nan, 36, c1, 'x', 'LineWidth', 1.8);  % leftward choice (cross)
    rtlast_R = scatter(ax_rtR, nan, nan, 36, 'MarkerEdgeColor',[0 0 0], ...
        'MarkerFaceColor','none', 'LineWidth', 2);     % hollow latest-trial ring
    xlabel(ax_rtR,'Onset asynchrony (ms)');
    ylabel(ax_rtR,'RT (s)');
    title(ax_rtR,'RT — Rightward onset first', 'FontSize', 15);
    rtxt_R  = text(ax_rtR, 0.98, 0.95, '', 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top','FontSize',10);

    % Stay toggle — see header. Only stores its state; acted on at the next
    % return to this task.
    uicontrol(fig2, 'Style', 'togglebutton', 'Units', 'normalized', ...
        'Position', [0.58, 0.965, 0.12, 0.030], ...
        'String', 'Stay', 'FontSize', 10, 'Value', stayDefault, ...
        'BackgroundColor', stayColor(stayDefault), 'ForegroundColor', [1 1 1], ...
        'Callback', @onStayToggle);

    % Superimpose + Clear buttons — top-right corner. Each sets a flag and
    % re-invokes this function so the action shows immediately rather than
    % waiting for the next trial.
    uicontrol(fig2, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.72, 0.965, 0.13, 0.030], ...
        'String', 'Superimpose', 'FontSize', 10, ...
        'BackgroundColor', [0.35 0.55 0.8], 'ForegroundColor', [1 1 1], ...
        'Callback', @(~,~) requestPsychAction(fig2, 'doSuperimpose', nFig));
    uicontrol(fig2, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.86, 0.965, 0.12, 0.030], ...
        'String', 'Clear', 'FontSize', 10, ...
        'BackgroundColor', [0.85 0.4 0.4], 'ForegroundColor', [1 1 1], ...
        'Callback', @(~,~) requestPsychAction(fig2, 'doClear', nFig));

    time_count = 0;
end

% --- New block after a task switch: plot only the returning trials ---
if ~isempty(newBlockOffset)
    fig2.UserData.trialOffset = newBlockOffset;
    pPrev = [];
    pWin  = [];
end

% --- Handle clear request: drop every period, restart at color 1 ---
if fig2.UserData.doClear
    fig2.UserData.trialOffset   = tsum.n;
    fig2.UserData.doClear       = false;
    fig2.UserData.doSuperimpose = false;
    fig2.UserData.period        = 1;
    fig2.UserData.xBase         = 0;
    fig2.UserData.nDone         = 0;
    fig2.UserData.corrBase      = 0;
    fig2.UserData.nCorrLive     = 0;
    htot.String = '';
    time_count = 0;
    pPrev      = [];      % drop the warm-start seeds with the data they came from
    pWin       = [];
    delete(frozenH(isgraphics(frozenH)));  frozenH = gobjects(0);
    oldLines = [bhAll(:); thAll(:)];
    delete(oldLines(isgraphics(oldLines)));
    [bhandle, thandle] = newBiasLines(ax2, ax3, periodColor(1));
    bhAll = bhandle;  thAll = thandle;
    delete(legH(isgraphics(legH)));
    legH = segmentProxy(ax1, periodColor(1), segmentLabel(1, 0, 0, NaN, NaN, true));
    buildSegLegend(ax1, legH);
    recolorLive(periodColor(1), [dhandle dlast rtdot_L rtx_L rtdot_R rtx_R], ...
        [nFit rtfit_L rtfit_R]);
    blankScatter(dhandle); blankScatter(dlast); clearpoints(nFit);
    blankScatter(rtdot_L); blankScatter(rtx_L); blankScatter(rtlast_L); clearpoints(rtfit_L); rtxt_L.String = '';
    blankScatter(rtdot_R); blankScatter(rtx_R); blankScatter(rtlast_R); clearpoints(rtfit_R); rtxt_R.String = '';
    drawnow;
    return;
end

% --- Handle superimpose request: freeze this period, start the next one ---
if fig2.UserData.doSuperimpose
    fig2.UserData.doSuperimpose = false;
    nPeriod = fig2.UserData.nDone;          % valid trials shown for this period
    if nPeriod >= 1                         % empty period -> nothing to freeze
        cOld = periodColor(fig2.UserData.period);
        frozenH = [frozenH; freezePeriod(cOld, ...
            [dhandle rtdot_L rtx_L rtdot_R rtx_R], [nFit rtfit_L rtfit_R])];

        xb = fig2.UserData.xBase + nPeriod;
        frozenH = [frozenH; ...
            xline(ax2, xb + 0.5, '--', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off'); ...
            xline(ax3, xb + 0.5, '--', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off')];

        fig2.UserData.xBase       = xb;
        fig2.UserData.corrBase    = fig2.UserData.corrBase + fig2.UserData.nCorrLive;
        fig2.UserData.nCorrLive   = 0;
        fig2.UserData.period      = fig2.UserData.period + 1;
        fig2.UserData.trialOffset = tsum.n;
        fig2.UserData.nDone       = 0;
        time_count = 0;
        pPrev      = [];
        pWin       = [];

        cNew = periodColor(fig2.UserData.period);
        [bhandle, thandle] = newBiasLines(ax2, ax3, cNew);
        bhAll(end+1) = bhandle;  thAll(end+1) = thandle;
        % Freeze the finished segment's legend row (drop the live marker) and
        % add a row for the new one.
        legH(end).DisplayName = strrep(legH(end).DisplayName, '*', ' ');
        legH(end+1) = segmentProxy(ax1, cNew, ...
            segmentLabel(fig2.UserData.period, 0, 0, NaN, NaN, true));
        buildSegLegend(ax1, legH);
        recolorLive(cNew, [dhandle dlast rtdot_L rtx_L rtdot_R rtx_R], ...
            [nFit rtfit_L rtfit_R]);
        blankScatter(dhandle); blankScatter(dlast); clearpoints(nFit);
        blankScatter(rtdot_L); blankScatter(rtx_L); blankScatter(rtlast_L); clearpoints(rtfit_L); rtxt_L.String = '';
        blankScatter(rtdot_R); blankScatter(rtx_R); blankScatter(rtlast_R); clearpoints(rtfit_R); rtxt_R.String = '';
        drawnow limitrate;
    end
    return;
end

% --- Apply trial offset (set by Clear / Superimpose) ---
% Indexes the numeric mirror `tsum`, which getJivesData appends in lockstep
% with `trials`, so the Clear-button offset semantics are unchanged.
offset = fig2.UserData.trialOffset;
if offset > 0 && offset + 1 <= tsum.n
    i0 = offset + 1;
else
    if offset >= tsum.n
        disp('plotJivesPsychometrics: trials refreshed externally — using full trials array');
        fig2.UserData.trialOffset = 0;
    end
    i0 = 1;
end
if tsum.n - i0 + 1 < 2; return; end

% --- Trials with a valid choice AND from the time-discrimination task ---
% Mirror the switchyard's dispatch predicate (contains(Task,'time')) so the
% psychometric never mixes in trials from other tasks (e.g. visual saccade),
% whose Requested_target_2_time_offset is NaN and would pollute the fit.
% isTimeTask was evaluated once per trial in getJivesData using the identical
% expression, replacing a per-tick arrayfun over the whole struct array.
sel   = i0 : tsum.n;
valid = ~isnan(tsum.choice(sel)) & tsum.isTimeTask(sel);
if isempty(valid) || valid(end)==0
    return
end

vIdx = sel(valid);
if isempty(vIdx); return; end

% Numeric choice (1 or 2)
chooseN = tsum.choice(vIdx);% 1 or 2

% Target direction: right = +1, left = -1 (computed per trial in getJivesData
% from Target_1_position, same cart2pol -> compass-degrees conversion)
direction = tsum.direction(vIdx); %1: right first, -1: left first


% Reaction time (ms) — row-oriented, as the RT panels below expect
hasRT = tsum.hasRT(vIdx).';
RT    = tsum.RT(vIdx).'; % in s

%Proportion of rightward choices
choiceLR = chooseN;
choiceLR(direction == 1 & chooseN==1) = 1; %rightward choices
choiceLR(direction == -1 & chooseN==1) = 0; %leftward choices
choiceLR(direction == -1 & chooseN==2) = 1; %rightward choices
choiceLR(direction == 1 & chooseN==2) = 0; %leftward choices

%Loop over the time asychrony
stimulus = tsum.stimulus(vIdx);
stimulus_dir = stimulus .* direction;
[stim_levels, ~, idx] = unique(stimulus_dir);
pRight = accumarray(idx, choiceLR==1, [], @mean);

TotalTrials = numel(vIdx);

% Fit only once BOTH onset-first conditions exist (points on both sides of
% zero asynchrony) — a sigmoid is unconstrained otherwise.
canFitPsy = any(stimulus_dir < 0) && any(stimulus_dir > 0);

if isempty(optz)
    optz = optimset('Display','off');      % built once, not every tick
end

if canFitPsy
    % Constrained logistic MLE (see fitLogisticMLE): slope = exp(g) > 0, so the
    % psychometric can never fit "reversed".
    % Adaptive iteration cap: few trials -> few iterations (fast, rough),
    % growing as data accumulates for a more accurate fit later.
    maxIter = min(400, 60 + 4*TotalTrials);
    optz.MaxIter    = maxIter;
    optz.MaxFunEvals = 2*maxIter;

    % Warm start from the previous tick's solution. One extra trial barely
    % moves the MLE, so the simplex converges in a handful of iterations
    % instead of rebuilding from scratch (up to 800 full-vector evaluations).
    if isempty(pPrev) || any(~isfinite(pPrev))
        p0 = [0, log(0.02)];                  % cold: zero bias, gentle slope
    else
        p0 = pPrev;
    end
    [b0, b1, pHat, validFit] = fitLogisticMLE(stimulus_dir(:), double(choiceLR(:) == 1), p0, optz);
    if validFit
        pPrev = pHat;                         % seed for the next tick
    else
        pPrev = [];                           % bad fit — cold start next time
    end
else
    validFit = false;
    b0 = NaN; b1 = NaN;
end

if validFit
    % Get bias and threshold
    [pse, threshold] = pseThreshold(b0, b1);

    %Fitted curve
    xx = linspace(-250, 250, 100);
    yy = 1./(1+exp(-(b0 + b1*xx)));      % fitted psy
else
    pse = NaN; threshold = NaN; xx = []; yy = [];
end

time_count = time_count + 1;

%Update the plot
% Marker AREA is proportional to trials-per-condition, normalized to the
% largest-count dot across ALL panels (shared rule in relDotSize). Compute
% every panel's counts up front so they share one scale (gMaxN).
nPerLevel = accumarray(idx, 1);       % # valid trials at each stimulus level

% RT-panel decompositions (hoisted so they feed the shared dot scale)
rtCol = RT'; hasRTcol = hasRT';
inL = (stimulus_dir <= 0) & hasRTcol; fillL = inL & (choiceLR == 0); crossL = inL & (choiceLR == 1);
inR = (stimulus_dir >= 0) & hasRTcol; fillR = inR & (choiceLR == 1); crossR = inR & (choiceLR == 0);
[levFL, mrtFL, nFL] = rtByLevel(stimulus_dir, rtCol, fillL);
[levXL, mrtXL, nXL] = rtByLevel(stimulus_dir, rtCol, crossL);
[levFR, mrtFR, nFR] = rtByLevel(stimulus_dir, rtCol, fillR);
[levXR, mrtXR, nXR] = rtByLevel(stimulus_dir, rtCol, crossR);
gMaxN = max([nPerLevel(:); nFL(:); nXL(:); nFR(:); nXR(:); 1]);

dotSz = relDotSize(nPerLevel, gMaxN);
set(dhandle, 'XData', stim_levels, 'YData', pRight, 'SizeData', dotSz);

% Outline the level updated by the most recent trial (idx(end) = its level)
iLast = idx(end);
set(dlast, 'XData', stim_levels(iLast), 'YData', pRight(iLast), 'SizeData', dotSz(iLast));

clearpoints( nFit);
if ~isempty(xx)
    addpoints( nFit, xx ,yy);
end

% Live segment's legend row: choice trials / correct (outcome bit 1, set by
% outcomeMask in getJivesData), PSE and threshold of the cumulative fit
nCorrect = sum(bitand(tsum.outcome(vIdx), uint8(1)) > 0);
legH(end).DisplayName = segmentLabel(fig2.UserData.period, TotalTrials, ...
    nCorrect, pse, threshold, true);
% Totals across segments: frozen segments (xBase / corrBase) + live one
fig2.UserData.nCorrLive = nCorrect;
htot.String = sprintf('Total N/Corr  %d/%d', ...
    fig2.UserData.xBase + TotalTrials, fig2.UserData.corrBase + nCorrect);


% --- Bias / Threshold: sliding window of N_WIN valid trials, step 1 ---
% One point per new valid trial k of this period (window max(1,k-N_WIN+1):k),
% so several trials arriving in one tick still each get their own point.
% x = valid-trial count since the last Clear (xBase + k).
nDone = fig2.UserData.nDone;
if TotalTrials > nDone
    % While k <= N_WIN the window IS the whole period, so the newest point is
    % exactly the cumulative fit above — reuse it instead of refitting.
    reuseMain = validFit && TotalTrials <= N_WIN;
    kTo = TotalTrials - reuseMain;
    [ks, pses, thrs, pWin] = computeSlidingBiasThresh(stimulus_dir, choiceLR, ...
        nDone + 1, kTo, N_WIN, pWin, optz);
    if reuseMain
        pWin = pPrev;
        if isfinite(pse) && isfinite(threshold)
            ks(end+1) = TotalTrials;  pses(end+1) = pse;  thrs(end+1) = threshold;
        end
    end
    if ~isempty(ks)
        addpoints(bhandle, fig2.UserData.xBase + ks, pses);
        addpoints(thandle, fig2.UserData.xBase + ks, thrs);
    end
    fig2.UserData.nDone = TotalTrials;
end

% --- RT vs asynchrony panels ---
% Decompositions (rtCol/hasRTcol, masks, per-level means/counts) were hoisted
% above so all panels share one dot scale (gMaxN). relSize closes over gMaxN.
relSize = @(nn) relDotSize(nn, gMaxN);

% choiceLR: 1 = rightward choice, 0 = leftward choice
% Each panel: choice MATCHING the onset-first side -> filled dots + fit;
% the opposite choice -> cross markers (no fit).
RT_FIT_MIN = 6;   % min trials in a choice group before its RT line is drawn

% --- Leftward onset first (stimulus_dir <= 0) ---
% Each object is written ONCE per tick. The previous version blanked these
% and then immediately re-set them a few lines later, costing two graphics
% invalidations per object where one does.
clearpoints(rtfit_L); rtxt_L.String = '';
blankScatter(rtlast_L);

if ~isempty(levFL)
    set(rtdot_L,'XData',levFL,'YData',mrtFL,'SizeData',relSize(nFL));
    if numel(levFL) >= 2 && sum(fillL) >= RT_FIT_MIN
        addpoints(rtfit_L, levFL, polyval(polyfit(levFL, mrtFL, 1), levFL));
        [rmatL, pmatL] = corrcoef(stimulus_dir(fillL), rtCol(fillL));
        rtxt_L.String = sprintf('r=%.2f  p=%.3f', rmatL(1,2), pmatL(1,2));
    end
else
    blankScatter(rtdot_L);
end
if ~isempty(levXL)
    set(rtx_L,'XData',levXL,'YData',mrtXL,'SizeData',relSize(nXL));
else
    blankScatter(rtx_L);
end
% encircle the most recent trial's point, on whichever group it belongs to
if hasRTcol(end) && stimulus_dir(end) <= 0
    if choiceLR(end) == 0
        ringRT(rtlast_L, levFL, mrtFL, nFL, stimulus_dir(end), relSize);
    else
        ringRT(rtlast_L, levXL, mrtXL, nXL, stimulus_dir(end), relSize);
    end
end

% --- Rightward onset first (stimulus_dir >= 0) ---
clearpoints(rtfit_R); rtxt_R.String = '';
blankScatter(rtlast_R);

if ~isempty(levFR)
    set(rtdot_R,'XData',levFR,'YData',mrtFR,'SizeData',relSize(nFR));
    if numel(levFR) >= 2 && sum(fillR) >= RT_FIT_MIN
        addpoints(rtfit_R, levFR, polyval(polyfit(levFR, mrtFR, 1), levFR));
        [rmatR, pmatR] = corrcoef(stimulus_dir(fillR), rtCol(fillR));
        rtxt_R.String = sprintf('r=%.2f  p=%.3f', rmatR(1,2), pmatR(1,2));
    end
else
    blankScatter(rtdot_R);
end
if ~isempty(levXR)
    set(rtx_R,'XData',levXR,'YData',mrtXR,'SizeData',relSize(nXR));
else
    blankScatter(rtx_R);
end
if hasRTcol(end) && stimulus_dir(end) >= 0
    if choiceLR(end) == 1
        ringRT(rtlast_R, levFR, mrtFR, nFR, stimulus_dir(end), relSize);
    else
        ringRT(rtlast_R, levXR, mrtXR, nXR, stimulus_dir(end), relSize);
    end
end

%hold off
% No drawnow here — jivesAnalysisSwitchyard issues one flush per tick.
%{
catch
    keyboard
end
%}
end

function requestPsychAction(fig, flag, nFig)
% Button callback: raise the deferred flag, then run the plot function once so
% the Clear / Superimpose takes effect now instead of on the next trial.
    if ~isempty(fig) && isvalid(fig)
        fig.UserData.(flag) = true;
        plotJivesPsychometrics(nFig);
    end
end

function onStayToggle(h, ~)
% Stay toggle callback: store the state on the figure and recolor the button.
    fig = ancestor(h, 'figure');
    fig.UserData.stay = logical(h.Value);
    h.BackgroundColor = stayColor(h.Value);
end

function c = stayColor(on)
% Green when Stay is pressed, gray when released.
if on; c = [0.3 0.7 0.4]; else; c = [0.6 0.6 0.6]; end
end

function freezeFigure(fig, name)
% Leave a finished block's figure on screen but inert: its buttons would
% otherwise drive the persistent state that now belongs to the new figure.
set(findall(fig, 'Type', 'uicontrol'), 'Enable', 'off');
fig.Name = name;
end

function g = lastForeignTrial(trials, i0, i1, isForeign)
% Index of the last trial in i0..i1 whose (non-empty) Task satisfies
% isForeign, or [] if none. Scans backwards so it stops at the first hit.
g = [];
for n = i1:-1:i0
    t = trials(n).Task;
    if ~isempty(t) && isForeign(t)
        g = n;
        return;
    end
end
end

function c = periodColor(k)
% Color of period k. Period 1 is the original red; cycles after 6 periods.
PALETTE = [0.85 0.10 0.10;    % red
           0.00 0.45 0.74;    % blue
           0.20 0.63 0.17;    % green
           0.93 0.57 0.13;    % orange
           0.49 0.18 0.56;    % purple
           0.30 0.75 0.93];   % cyan
c = PALETTE(mod(k-1, size(PALETTE,1)) + 1, :);
end

function [bh, th] = newBiasLines(ax2, ax3, c)
% Fresh bias / threshold animatedlines for one period.
bh = animatedline(ax2, 'Color', c, 'Marker', '.', 'LineStyle', '-', 'DisplayName', 'Bias');
th = animatedline(ax3, 'Color', c, 'Marker', '.', 'LineStyle', '-', 'DisplayName', 'Threshold');
end

function recolorLive(c, scatters, alines)
% Point the live (current-period) objects at period color c. CData drives the
% fill of 'filled' scatters and the edge of 'x' scatters; black edges/rings
% set explicitly are untouched.
set(scatters, 'CData', c);
set(alines, 'Color', c);
end

function h = segmentProxy(ax, c, label)
% Invisible (NaN) line that only exists to give a segment its legend row.
h = line(ax, NaN, NaN, 'Color', c, 'LineWidth', 2.5, 'DisplayName', label);
end

function lg = buildSegLegend(ax, legH)
% (Re)build the segment legend from the proxies. Fixed-width font keeps the
% columns aligned with the title row; no box so it never hides data behind it;
% AutoUpdate off so later plotted objects (frozen copies etc.) are not added.
% Newest (live) segment first, so it always sits right under the header.
lg = legend(ax, flip(legH), 'Location', 'northwest', 'Box', 'off', ...
    'FontName', 'FixedWidth', 'FontSize', 9, 'Interpreter', 'none', ...
    'AutoUpdate', 'off');
lg.Title.String     = sprintf('%-3s %9s %8s %8s', 'Seg', 'N/Corr', 'PSE(ms)', 'Thr(ms)');
lg.Title.FontName   = 'FixedWidth';
lg.Title.FontWeight = 'normal';
end

function s = segmentLabel(k, nChoice, nCorrect, pse, thr, isLive)
% One legend row: segment k (live one marked '*'), choice trials / correct,
% PSE and threshold of the segment's cumulative fit ('--' when no valid fit).
if isLive; mark = '*'; else; mark = ' '; end
s = sprintf('S%d%s %9s %8s %8s', k, mark, sprintf('%d/%d', nChoice, nCorrect), ...
    fmtFit(pse), fmtFit(thr));
end

function s = fmtFit(v)
if isfinite(v); s = sprintf('%.1f', v); else; s = '--'; end
end

function h = freezePeriod(c, scatters, alines)
% Static copies of the current period's dots and fit lines, drawn in color c
% and pushed under the live objects. Returns the new handles (column).
h = gobjects(0, 1);
for s = scatters
    if ~isempty(s.XData) && any(~isnan(s.XData))
        h(end+1, 1) = copyobj(s, s.Parent); %#ok<AGROW>
        set(h(end), 'CData', c, 'HandleVisibility', 'off');
    end
end
for a = alines
    [x, y] = getpoints(a);
    if ~isempty(x)
        h(end+1, 1) = line(a.Parent, x, y, 'Color', c, 'LineWidth', a.LineWidth, ...
            'HandleVisibility', 'off'); %#ok<AGROW>
    end
end
for j = 1:numel(h)          % uistack needs one parent per call
    uistack(h(j), 'bottom');
end
end

function [b0, b1, pHat, ok] = fitLogisticMLE(x, y, p0, optz)
% Constrained logistic MLE: parameterise the slope as b1 = exp(g), so the
% slope is POSITIVE by construction and the psychometric can never fit
% "reversed" (negative slope / negative threshold). Unconstrained ML over
% [b0, g] via fminsearch (base MATLAB) on the Bernoulli neg-log-likelihood.
% x: signed asynchrony (column), y: 1 = rightward choice (column).
softplus = @(z) max(z,0) + log1p(exp(-abs(z)));   % stable log(1+exp(z))
nll = @(p) sum( softplus(p(1) + exp(p(2)).*x) - y.*(p(1) + exp(p(2)).*x) );
pHat = fminsearch(nll, p0, optz);
b0 = pHat(1);
b1 = exp(pHat(2));                                  % > 0 by construction
ok = isfinite(b0) && isfinite(b1) && b1 > 0;
end

function [pse, threshold] = pseThreshold(b0, b1)
% PSE (bias) and threshold of the logistic fit, NaN when implausibly large.
pse = -b0 / b1;
threshold = 1/b1;
if abs(pse) > 500
    pse = NaN;
end
if abs(threshold) > 1000
    threshold = NaN;
end
end

function [ks, pses, thrs, pWin] = computeSlidingBiasThresh(stimDir, choiceLR, kFrom, kTo, N, pWin, optz)
% Bias / threshold for each window ending at k = kFrom..kTo, where window k is
% trials max(1,k-N+1):k (grows until N trials, then slides by one). Windows
% without stimuli on both sides of zero, or with an invalid / out-of-range
% fit, are skipped. pWin is the warm-start seed, returned updated.
stimDir = stimDir(:);
y = double(choiceLR(:) == 1);
ks = [];  pses = [];  thrs = [];
for k = kFrom:kTo
    w = max(1, k-N+1):k;
    sx = stimDir(w);
    if ~(any(sx < 0) && any(sx > 0)); continue; end
    maxIter = min(400, 60 + 4*numel(w));
    optz.MaxIter     = maxIter;
    optz.MaxFunEvals = 2*maxIter;
    if isempty(pWin) || any(~isfinite(pWin))
        p0 = [0, log(0.02)];
    else
        p0 = pWin;
    end
    [b0, b1, pHat, ok] = fitLogisticMLE(sx, y(w), p0, optz);
    if ~ok
        pWin = [];
        continue;
    end
    pWin = pHat;
    [pse, thr] = pseThreshold(b0, b1);
    if isfinite(pse) && isfinite(thr)
        ks(end+1) = k;  pses(end+1) = pse;  thrs(end+1) = thr; %#ok<AGROW>
    end
end
end

function sz = relDotSize(n, maxN)
% Scatter marker AREA proportional to trial count, normalized so the dot with
% the most trials (maxN, shared across all panels) is drawn at MAX_DOT. Strictly
% proportional: a 3-trial dot has 3x the area of a 1-trial dot. No floor/plateau.
MAX_DOT = 300;                 % area of the largest-count dot (tunable)
if isempty(n); sz = []; return; end
if maxN < 1; maxN = 1; end
sz = MAX_DOT * (n(:) / maxN);
end

function [lev, mrt, n] = rtByLevel(stim, rt, mask)
% Mean RT and trial count per unique asynchrony level, over the masked trials.
s = stim(mask);  r = rt(mask);
if isempty(s)
    lev = [];  mrt = [];  n = [];
    return;
end
[lev, ~, ix] = unique(s);
mrt = accumarray(ix, r, [], @mean);
n   = accumarray(ix, 1);
end

function s = ringSize(markerArea)
% Hollow ring area that encircles (sits outside) a marker of markerArea.
s = markerArea*2 + 40;
end

function blankScatter(h)
% Blank a scatter object. SizeData must be reset along with XData/YData:
% these scatters carry a per-point size vector (dot area encodes trials per
% level), and leaving a stale N-element SizeData against empty coordinates
% makes the renderer emit "Data lengths must match" warnings.
set(h, 'XData', [], 'YData', [], 'SizeData', 36);
end


function ringRT(h, lev, mrt, n, x, sizeFcn)
% Position the hollow latest-trial ring h at asynchrony level x (if present),
% sized to encircle a marker drawn with sizeFcn (the relSize handle over relDotSize).
i = find(lev == x, 1);
if ~isempty(i)
    set(h, 'XData', lev(i), 'YData', mrt(i), 'SizeData', ringSize(sizeFcn(n(i))));
end
end

%{
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
%}
