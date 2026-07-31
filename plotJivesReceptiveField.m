function plotJivesReceptiveField(nFig)
% RF heatmap (center) + 16 spatial PSTHs arranged by target angle and eccentricity.
% "All" unit mode merges spikes from all sorted units; single-unit mode uses one.
% PSTH alignment (visual onset or go signal) chosen via dialog/button.
%
% Layout — manual axes, all 16 PSTH panels equal size (pw × ph):
%   Row 1 (top far):   [NW-far]          [N-far]           [NE-far]
%   Row 2 (top near):  [NW-near]         [N-near]          [NE-near]
%   Mid:               [W-far][W-near] [  HEATMAP  ] [E-near][E-far]
%   Row 4 (bot near):  [SW-near]         [S-near]          [SE-near]
%   Row 5 (bot far):   [SW-far]          [S-far]           [SE-far]
% W/E panels are vertically centered with the heatmap.
%
% 8 equal 45° direction sectors × 2 eccentricity bins (< ECC_NEAR, ≥ ECC_NEAR).

% Spike timestamps live in the parallel global `spikeTrials` (flat .ts/.ch/
% .unit arrays per trial), not inside `trials`. spikeNCh / spikeNUnits carry
% the spike-buffer dimensions and are what size the channel/unit dropdowns —
% they must come from the buffer, not from the spikes actually present, or
% the channel list would shrink whenever activity is sparse.
global trials spikeTrials spikeNCh spikeNUnits

% ── Constants ─────────────────────────────────────────────────────────────
RF_WIN_MS    = [50, 250];
VIS_WIN_MS   = [-200, 600];
GO_WIN_MS    = [-400, 300];
BIN_MS       = 10;
PSTH_SIGMA   = 20;
SMOOTH_SIGMA = 2.5;
GRID_EDGES   = -20:1:20;
GRID_CTRS    = (GRID_EDGES(1:end-1) + GRID_EDGES(2:end)) / 2;
FIX_COLOR    = [1 0 0];
CTRL_H       = 60;
ECC_NEAR     = 10;   % deg; near < ECC_NEAR, far >= ECC_NEAR

N_SECTORS = 16;
% Sector centre angles and ecc bins in axPS index order (1–16)
SECTOR_ANGLES = [135, 90, 45, 135, 90, 45, 180, 0, 180, 0, 225, 270, 315, 225, 270, 315];
SECTOR_NEAR   = logical([0,0,0, 1,1,1, 0,0,1,1, 1,1,1, 0,0,0]);
deg = char(176);
SECTOR_LABELS = cell(N_SECTORS, 1);
for k = 1:N_SECTORS
    if SECTOR_NEAR(k); ineq = '<'; else; ineq = '>'; end
    SECTOR_LABELS{k} = sprintf('%d%s, %s%d', SECTOR_ANGLES(k), deg, ineq, ECC_NEAR);
end

% ── Persistent state ──────────────────────────────────────────────────────
persistent fig hChDD hUnitDD hRFt0 hRFt1 hPSTHt0 hPSTHt1 hAlignDD ...
           axHM axPS ...
           lastNCh lastNUnits ...
           gridFR gridN nRFcorrect lastRFTrial lastRFch lastRFunitSel lastRFwin lastRFalign ...
           tgt_xy lastTgtTrial ...
           psthN psthMean psthM2 ...
           lastPSTHTrial lastPSTHch lastPSTHunitSel lastPSTHwin lastPSTHalign ...
           activeRFTask clearWatermark ...
           hFillPS hLinePS hZeroPS hImg hTgt hEll hCross hLbl ...
           lastSharedYLim lastPanelTitle needFullDraw ...
           gridFRsmCache lastSmoothN

if isempty(trials); return; end

% ── Task gate: freeze figure if task has changed ──────────────────────────
if ~isfield(trials(end), 'Task') || isempty(trials(end).Task)
    return;                                % task not yet known — wait for next tick
end
if isempty(activeRFTask)
    activeRFTask = trials(end).Task;       % adopt task on first run / after Clear All
elseif ~isequal(trials(end).Task, activeRFTask)
    return;                                % wrong task — keep display frozen
end

% ── Read UI state (defaults before figure exists) ──────────────────────────
alignOpts = {'Visual onset', 'Go signal (saccade)'};

if isempty(fig) || ~isvalid(fig)
    chSel    = 1;
    unitSel  = -1;
    rfWin    = RF_WIN_MS;
    psthWin  = VIS_WIN_MS;
    alignStr = alignOpts{1};
else
    chSel = hChDD.Value;
    if hUnitDD.Value == numel(hUnitDD.String)
        unitSel = -1;
    else
        unitSel = hUnitDD.Value;
    end
    rfWin    = [str2double(hRFt0.String),   str2double(hRFt1.String)];
    psthWin  = [str2double(hPSTHt0.String), str2double(hPSTHt1.String)];
    alignStr = alignOpts{hAlignDD.Value};
    if any(isnan(rfWin));   rfWin   = RF_WIN_MS;  end
    if any(isnan(psthWin)); psthWin = VIS_WIN_MS; end
end

% ── Build figure once ─────────────────────────────────────────────────────
if isempty(fig) || ~isvalid(fig)
    fig = figure(nFig);
    clf(fig);
    fig.UserData = struct('doFullClear', false, 'doFitRF', false, 'rfFit', []);
    set(fig, 'Position',[100 50 1400 960], ...
             'Name','Jives RF — Spatial PSTHs','NumberTitle','off');
    figH = fig.Position(4);
    fd   = 1 - CTRL_H/figH;

    CB = @(~,~) plotJivesReceptiveField(nFig);
    y  = figH - CTRL_H + 20;
    ye = figH - CTRL_H + 22;

    % Channel
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[20 y 30 22],'String','Ch:', ...
        'HorizontalAlignment','right','FontSize',11);
    % Seed from the live channel count; the refresh block below keeps it in
    % sync. (Previously hard-coded to 96, which was wrong at 256 channels
    % until the refresh path happened to run.)
    if isempty(spikeNCh) || spikeNCh < 1; nChSeed = 1; else; nChSeed = spikeNCh; end
    hChDD = uicontrol(fig,'Style','popupmenu','Units','pixels', ...
        'Position',[54 ye 80 22],'String',arrayfun(@num2str,1:nChSeed,'uni',0), ...
        'Value',1,'FontSize',11,'Callback',CB);

    % Unit
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[145 y 38 22],'String','Unit:', ...
        'HorizontalAlignment','right','FontSize',11);
    hUnitDD = uicontrol(fig,'Style','popupmenu','Units','pixels', ...
        'Position',[187 ye 80 22],'String',{'all'}, ...
        'Value',1,'FontSize',11,'Callback',CB);

    % RF window
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[285 y 28 22],'String','RF:', ...
        'HorizontalAlignment','right','FontSize',10);
    hRFt0 = uicontrol(fig,'Style','edit','Units','pixels', ...
        'Position',[317 ye 50 22],'String',num2str(RF_WIN_MS(1)), ...
        'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[370 y 18 22],'String','to','FontSize',10);
    hRFt1 = uicontrol(fig,'Style','edit','Units','pixels', ...
        'Position',[391 ye 50 22],'String',num2str(RF_WIN_MS(2)), ...
        'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[444 y 22 22],'String','ms','FontSize',10);

    % PSTH window
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[490 y 38 22],'String','PSTH:', ...
        'HorizontalAlignment','right','FontSize',10);
    hPSTHt0 = uicontrol(fig,'Style','edit','Units','pixels', ...
        'Position',[532 ye 55 22],'String',num2str(psthWin(1)), ...
        'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[590 y 18 22],'String','to','FontSize',10);
    hPSTHt1 = uicontrol(fig,'Style','edit','Units','pixels', ...
        'Position',[611 ye 55 22],'String',num2str(psthWin(2)), ...
        'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[669 y 22 22],'String','ms','FontSize',10);

    % Alignment dropdown
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[710 y 44 22],'String','Align:', ...
        'HorizontalAlignment','right','FontSize',10);
    hAlignDD = uicontrol(fig,'Style','popupmenu','Units','pixels', ...
        'Position',[758 ye 160 22],'String',alignOpts, ...
        'Value',1,'FontSize',10,'Callback',CB);

    % Clear / Fit buttons
    uicontrol(fig,'Style','pushbutton','Units','pixels', ...
        'Position',[935 ye 85 22],'String','Clear All', ...
        'FontSize',10,'BackgroundColor',[0.85 0.4 0.4], ...
        'ForegroundColor',[1 1 1], ...
        'Callback',@(~,~) clearAllAndRedraw(fig, nFig));
    uicontrol(fig,'Style','pushbutton','Units','pixels', ...
        'Position',[1028 ye 70 22],'String','Fit RF', ...
        'FontSize',10,'BackgroundColor',[0.3 0.7 0.4], ...
        'ForegroundColor',[1 1 1], ...
        'Callback',@(~,~) fitRFAndRedraw(fig, nFig));

    % Plot area — manual axes so every PSTH panel has identical dimensions
    pPlot = uipanel(fig,'Units','normalized','Position',[0,0,1,fd], ...
                    'BorderType','none','BackgroundColor',get(fig,'Color'));

    % Layout constants (normalized within pPlot, y=0 at bottom)
    pw = 0.125;  ph = 0.135;   % panel width / height — same for all 16 PSTH axes
    gx = 0.010;  gy = 0.012;   % horizontal / vertical gap
    gySep = 0.030;             % larger gap between near/far pair rows (top and bottom)
    gyHM  = 0.050;             % gap between heatmap and adjacent panel rows
    lm = 0.065;  rm = 0.010;
    bm = 0.020;  tm = 0.020;

    % 5 vertical row positions (bottom edge of each panel row)
    y5 = bm;                          % SW-far / S-far / SE-far  (bottom)
    y4 = y5 + ph + gySep;             % SW-near / S-near / SE-near
    y3 = y4 + ph + gyHM;              % heatmap bottom edge
    hmh = 2*ph + gy;                  % heatmap height = 2 panel heights
    y2 = y3 + hmh + 3*gy;            % NW-near / N-near / NE-near (extra gap clears heatmap title)
    y1 = y2 + ph + gySep;             % NW-far / N-far / NE-far  (top)
    yWE = y3 + (hmh - ph)/2;         % W/E panels: vertically centered with heatmap

    % Horizontal column positions (left edge)
    x1L = lm;                          % far-left
    x2L = x1L + pw + gx;              % near-left
    x6R = 1 - rm - pw;                % far-right
    x5R = x6R - pw - gx;              % near-right
    hmx = x2L + pw + gx;              % heatmap left edge
    hmw = x5R - gx - hmx;             % heatmap width
    xNS = hmx + hmw/2 - pw/2;         % N/S panels centered over heatmap

    axHM = axes(pPlot,'Units','normalized','Position',[hmx, y3,  hmw, hmh]);

    axPS     = gobjects(N_SECTORS, 1);
    axPS(1)  = axes(pPlot,'Units','normalized','Position',[x1L, y1,  pw, ph]); % NW-far
    axPS(2)  = axes(pPlot,'Units','normalized','Position',[xNS, y1,  pw, ph]); % N-far
    axPS(3)  = axes(pPlot,'Units','normalized','Position',[x6R, y1,  pw, ph]); % NE-far
    axPS(4)  = axes(pPlot,'Units','normalized','Position',[x2L, y2,  pw, ph]); % NW-near (near-left col)
    axPS(5)  = axes(pPlot,'Units','normalized','Position',[xNS, y2,  pw, ph]); % N-near
    axPS(6)  = axes(pPlot,'Units','normalized','Position',[x5R, y2,  pw, ph]); % NE-near (near-right col)
    axPS(7)  = axes(pPlot,'Units','normalized','Position',[x1L, yWE, pw, ph]); % W-far
    axPS(9)  = axes(pPlot,'Units','normalized','Position',[x2L, yWE, pw, ph]); % W-near
    axPS(10) = axes(pPlot,'Units','normalized','Position',[x5R, yWE, pw, ph]); % E-near
    axPS(8)  = axes(pPlot,'Units','normalized','Position',[x6R, yWE, pw, ph]); % E-far
    axPS(11) = axes(pPlot,'Units','normalized','Position',[x2L, y4,  pw, ph]); % SW-near (near-left col)
    axPS(12) = axes(pPlot,'Units','normalized','Position',[xNS, y4,  pw, ph]); % S-near
    axPS(13) = axes(pPlot,'Units','normalized','Position',[x5R, y4,  pw, ph]); % SE-near (near-right col)
    axPS(14) = axes(pPlot,'Units','normalized','Position',[x1L, y5,  pw, ph]); % SW-far
    axPS(15) = axes(pPlot,'Units','normalized','Position',[xNS, y5,  pw, ph]); % S-far
    axPS(16) = axes(pPlot,'Units','normalized','Position',[x6R, y5,  pw, ph]); % SE-far

    lastNCh = [];  lastNUnits = [];
    % Everything must be painted once on the tick that creates the axes.
    needFullDraw   = true;
    lastSharedYLim = [];
    lastPanelTitle = repmat({''}, N_SECTORS, 1);
    hFillPS = gobjects(N_SECTORS,1);
    hLinePS = gobjects(N_SECTORS,1);
    hZeroPS = gobjects(N_SECTORS,1);
    hImg = gobjects(0); hTgt = gobjects(0); hEll = gobjects(0);
    hCross = gobjects(0); hLbl = gobjects(0);
    gridFRsmCache = []; lastSmoothN = -1;
end

% ── Refresh channel/unit dropdowns ────────────────────────────────────────
% Sized from the spike-BUFFER dimensions, which are the full channel/unit
% count regardless of which channels fired on the most recent trial.
if ~isempty(spikeNCh) && spikeNCh >= 1
    nCh = spikeNCh;
    if isempty(lastNCh) || lastNCh ~= nCh
        hChDD.String = arrayfun(@num2str, 1:nCh, 'uni', 0);
        hChDD.Value  = min(chSel, nCh);
        chSel        = hChDD.Value;
        lastNCh      = nCh;
    end
    nUnits = max(0, spikeNUnits);   % every col is a unit (col 1 = unsorted, col 2+ = sorted)
    if isempty(lastNUnits) || lastNUnits ~= nUnits
        unitStrs = [arrayfun(@num2str, 1:nUnits, 'uni', 0), {'all'}];
        hUnitDD.String = unitStrs;
        hUnitDD.Value  = min(hUnitDD.Value, numel(unitStrs));
        lastNUnits = nUnits;
    end
end

% Re-read unitSel after potential dropdown update
if hUnitDD.Value == numel(hUnitDD.String)
    unitSel = -1;
else
    unitSel = hUnitDD.Value;
end

% ── Gaussian PSTH kernel ──────────────────────────────────────────────────
sig_bins = PSTH_SIGMA / BIN_MS;
kSz  = 2*ceil(3*sig_bins) + 1;
kern = exp(-0.5*((-floor(kSz/2):floor(kSz/2))/sig_bins).^2);
kern = kern / sum(kern);

t_edges_psth = psthWin(1) : BIN_MS : psthWin(2);
t_c_psth     = t_edges_psth(1:end-1) + BIN_MS/2;
nBins        = numel(t_c_psth);

% ── Detect parameter changes → full recompute ─────────────────────────────
forceClear = isfield(fig.UserData, 'doFullClear') && fig.UserData.doFullClear;
if forceClear
    fig.UserData.doFullClear = false;
    fig.UserData.rfFit       = [];
    activeRFTask = [];
end

rfChanged   = forceClear                          || ...
              ~isequal(lastRFch,      chSel)      || ...
              ~isequal(lastRFunitSel, unitSel)    || ...
              ~isequal(lastRFwin,     rfWin)       || ...
              ~isequal(lastRFalign,   alignStr);
psthChanged = forceClear                          || ...
              ~isequal(lastPSTHch,      chSel)    || ...
              ~isequal(lastPSTHunitSel, unitSel)  || ...
              ~isequal(lastPSTHwin,     psthWin)  || ...
              ~isequal(lastPSTHalign,   alignStr);

% ── Snapshot current trial count before any reset ────────────────────────
nTrials = numel(trials);
if isempty(clearWatermark); clearWatermark = 0; end

% ── Reset RF accumulators ─────────────────────────────────────────────────
nG = numel(GRID_EDGES) - 1;
if rfChanged || isempty(gridFR)
    gridFR             = nan(nG, nG);
    gridN              = zeros(nG, nG);
    nRFcorrect         = 0;
    tgt_xy             = [];
    fig.UserData.rfFit = [];   % invalidate any existing fit
    lastRFch      = chSel;
    lastRFunitSel = unitSel;
    lastRFwin     = rfWin;
    lastRFalign   = alignStr;
    if forceClear
        clearWatermark = nTrials;
        rfStart        = nTrials + 1;
        lastRFTrial    = nTrials;
        lastTgtTrial   = nTrials;
    else
        wm           = max(0, clearWatermark);   % 0 before any Clear All
        rfStart      = wm + 1;
        lastRFTrial  = wm;
        lastTgtTrial = wm;
    end
else
    rfStart = lastRFTrial + 1;
end

% ── Reset PSTH accumulators ───────────────────────────────────────────────
if psthChanged || isempty(psthN) || size(psthMean, 2) ~= nBins
    psthN    = zeros(N_SECTORS, 1);
    psthMean = zeros(N_SECTORS, nBins);
    psthM2   = zeros(N_SECTORS, nBins);
    lastPSTHch      = chSel;
    lastPSTHunitSel = unitSel;
    lastPSTHwin     = psthWin;
    lastPSTHalign   = alignStr;
    if forceClear
        psthStart     = nTrials + 1;
        lastPSTHTrial = nTrials;
    else
        wm            = max(0, clearWatermark);
        psthStart     = wm + 1;
        lastPSTHTrial = wm;
    end
else
    psthStart = lastPSTHTrial + 1;
end

winSec = rfWin / 1000;
winDur = diff(rfWin) / 1000;

% ── Early exit if nothing to do ──────────────────────────────────────────
% A pending Fit RF must keep us alive: the button sets doFitRF and re-invokes
% immediately, so if this returned early the flag would sit unconsumed and
% the fit would not appear until the next trial happened to arrive.
fitPending = isfield(fig.UserData,'doFitRF') && fig.UserData.doFitRF;
loopStart  = min(rfStart, psthStart);
if loopStart > nTrials && ~rfChanged && ~psthChanged && ~forceClear && ~fitPending
    return;   % no new trials, no parameter change — display already current
end

% ── Incremental accumulation ─────────────────────────────────────────────
% Sectors whose PSTH accumulator changes on this pass. Only these panels are
% repainted below. A parameter change or a Clear resets the accumulators, so
% in that case every panel must be repainted regardless of what arrived.
dirtySec = false(N_SECTORS, 1);
if psthChanged || forceClear || needFullDraw
    dirtySec(:) = true;
end

for n = loopStart : nTrials
    if ~isfield(trials(n), 'Task')         || ~isequal(trials(n).Task, activeRFTask); continue; end
    if n > numel(spikeTrials); continue; end
    correct = isfield(trials(n), 'Trialoutcome') && ischar(trials(n).Trialoutcome) && ...
              contains(trials(n).Trialoutcome, 'correct');

    % Select this trial's spikes as a contiguous slice via the channel offset
    % table. Spikes are grouped by channel and time-ordered within a channel,
    % so this needs no mask over the whole trial and no sort() — in "all
    % units" mode the slice is already in time order.
    S = spikeTrials(n);
    if isempty(S.ts) || chSel + 1 > numel(S.chStart)
        allSpks = zeros(0, 1);
    else
        a = double(S.chStart(chSel));
        b = double(S.chStart(chSel+1)) - 1;
        if b < a
            allSpks = zeros(0, 1);
        elseif unitSel == -1
            allSpks = S.ts(a:b);
        else
            seg     = a:b;
            allSpks = S.ts(seg(S.unit(seg) == unitSel));
        end
    end

    % RF grid (correct trials only)
    if n >= rfStart && correct
        nRFcorrect = nRFcorrect + 1;
        t0go = trials(n).Fixation_point_off;
        for kt = 1:2
            xy = trials(n).(sprintf('Target_%d_position', kt));
            if any(isnan(xy)); continue; end
            if strcmp(alignStr, 'Visual onset')
                t0 = trials(n).(sprintf('Target_%d_presented', kt));
            else
                t0 = t0go;
            end
            if isnan(t0); continue; end
            ix = discretize(xy(1), GRID_EDGES);
            iy = discretize(xy(2), GRID_EDGES);
            if isnan(ix) || isnan(iy); continue; end
            w   = t0 + winSec;
            fr  = sum(allSpks >= w(1) & allSpks <= w(2)) / winDur;
            cnt = gridN(iy, ix);
            cur = gridFR(iy, ix); if isnan(cur); cur = 0; end
            gridFR(iy, ix) = (cur*cnt + fr) / (cnt + 1);
            gridN(iy, ix)  = cnt + 1;
        end
    end

    % Target overlay positions (all trials)
    if n > lastTgtTrial
        for kt = 1:2
            t0 = trials(n).(sprintf('Target_%d_presented', kt));
            xy = trials(n).(sprintf('Target_%d_position',  kt));
            if ~isnan(t0) && ~any(isnan(xy))
                tgt_xy = [tgt_xy; xy]; %#ok<AGROW>
            end
        end
    end

    % Spatial PSTHs — one Welford update per target per trial (correct only)
    if n >= psthStart && correct
        t0go = trials(n).Fixation_point_off;
        for kt = 1:2
            xy  = trials(n).(sprintf('Target_%d_position',  kt));
            t0v = trials(n).(sprintf('Target_%d_presented', kt));
            if isnan(t0v) || any(isnan(xy)); continue; end
            if strcmp(alignStr, 'Visual onset')
                t0ev = t0v;
            else
                t0ev = t0go;
            end
            if isnan(t0ev); continue; end

            ecc  = hypot(xy(1), xy(2));
            ang  = atan2d(xy(2), xy(1));
            sIdx = getSectorIdx(ang, ecc, ECC_NEAR);
            if isnan(sIdx); continue; end

            if isempty(allSpks)
                cnt = zeros(1, nBins);
            else
                cnt = histcounts((allSpks - t0ev)*1000, t_edges_psth);
            end
            fr = cnt / (BIN_MS / 1000);

            psthN(sIdx)       = psthN(sIdx) + 1;
            delta             = fr - psthMean(sIdx,:);
            psthMean(sIdx,:)  = psthMean(sIdx,:) + delta / psthN(sIdx);
            psthM2(sIdx,:)    = psthM2(sIdx,:) + delta .* (fr - psthMean(sIdx,:));
            dirtySec(sIdx)    = true;
        end
    end
end

lastRFTrial   = nTrials;
lastTgtTrial  = nTrials;
lastPSTHTrial = nTrials;
if ~isempty(tgt_xy); tgt_xy = unique(tgt_xy, 'rows'); end

% ── Smooth RF for display ─────────────────────────────────────────────────
% Extrapolate only after RF_EXTRAP_MIN correct trials (~2 obs per trial)
RF_EXTRAP_MIN = 10;
hasData   = ~isnan(gridFR);
nPts      = sum(hasData(:));
nRFobs    = sum(gridN(:));          % total target-onset observations

% Rebuilding the interpolant and re-filtering the 40x40 grid on every tick is
% wasted work — a single trial barely moves the map. Refresh once enough new
% observations have landed, and always when a parameter change, a Clear or a
% pending RF fit means the cached map can no longer be trusted.
RF_SMOOTH_EVERY = 5;                % observations between refreshes
needSmooth = isempty(gridFRsmCache) || rfChanged || forceClear || ...
             needFullDraw || fitPending || ...
             (nRFobs - lastSmoothN) >= RF_SMOOTH_EVERY;

if needSmooth
    [gxm, gym] = meshgrid(GRID_CTRS, GRID_CTRS);
    if nPts >= 3 && nRFobs >= 2 * RF_EXTRAP_MIN
        % Enough data: natural-neighbor interpolation inside hull, nearest outside
        F = scatteredInterpolant(gxm(hasData), gym(hasData), ...
                                 double(gridFR(hasData)), 'natural', 'nearest');
        gridFR_sm = imgaussfilt(F(gxm, gym), SMOOTH_SIGMA);
    elseif nPts >= 1
        % Early trials: NaN-aware smoothing, no extrapolation into empty regions
        dataMap   = gridFR; dataMap(~hasData) = 0;
        smoothNum = imgaussfilt(dataMap,          SMOOTH_SIGMA);
        smoothDen = imgaussfilt(double(hasData),  SMOOTH_SIGMA);
        gridFR_sm = smoothNum ./ max(smoothDen, 1e-6);
        gridFR_sm(smoothDen < 0.02) = 0;
    else
        gridFR_sm = zeros(size(gridFR));
    end
    gridFRsmCache = gridFR_sm;
    lastSmoothN   = nRFobs;
else
    gridFR_sm = gridFRsmCache;
end

% ── 2-D Gaussian fit (triggered by Fit RF button) ────────────────────────
if isfield(fig.UserData,'doFitRF') && fig.UserData.doFitRF
    fig.UserData.doFitRF = false;
    fig.UserData.rfFit   = fitGaussian2D(gridFR_sm, GRID_CTRS);
end

% ── Smoothed PSTH mean ± SEM ──────────────────────────────────────────────
smMean = zeros(N_SECTORS, nBins);
smSEM  = zeros(N_SECTORS, nBins);
for s = 1:N_SECTORS
    smMean(s,:) = conv(psthMean(s,:), kern, 'same');
    if psthN(s) > 1
        smSEM(s,:) = conv(sqrt(psthM2(s,:)/(psthN(s)-1)) / sqrt(psthN(s)), ...
                          kern, 'same');
    end
end

% ── Guard: skip drawing if figure or axes were closed ─────────────────────
if ~isvalid(fig) || ~isvalid(axHM) || any(~isvalid(axPS))
    return;
end

% ── Draw heatmap (reuse objects — no cla) ─────────────────────────────────
% Handles are cached in persistents rather than re-found with findobj on
% every tick (that was ~5 hierarchy searches here plus 3 per PSTH panel).
if isempty(hImg) || ~isgraphics(hImg)
    hold(axHM,'on');
    hImg = imagesc(axHM, GRID_CTRS, GRID_CTRS, gridFR_sm); hImg.Tag = 'rf_img';
    axis(axHM, [-20 20 -20 20]); axis(axHM,'equal'); axis(axHM,'square');
    scatter(axHM, 0, 0, 30, FIX_COLOR, 'filled', 'Tag','rf_fix');
    hTgt   = scatter(axHM, nan, nan, 60, 'w','o','LineWidth',1.5,'Tag','rf_tgt');
    hEll   = plot(axHM, nan, nan, 'w-','LineWidth',2,'Tag','rf_ell');
    hCross = plot(axHM, nan, nan, 'r+','MarkerSize',16,'LineWidth',2.5,'Tag','rf_cross');
    hLbl   = text(axHM, 0, 0, '', 'Color','w','FontSize',9,'FontWeight','bold', ...
         'HorizontalAlignment','center','VerticalAlignment','top', ...
         'Tag','rf_lbl','Visible','off');
    colormap(axHM,'parula');
    % Axis limits are fixed — set once here, not pushed on every tick.
    set(axHM,'YDir','normal','XTick',[],'YTick',[], ...
             'XLim',[-20 20],'YLim',[-20 20],'SortMethod','childorder');
    box(axHM,'on');
    cb = colorbar(axHM,'Location','eastoutside','FontSize',7);
    cb.Label.String = 'FR (sp/s)';  cb.Label.FontSize = 7;
else
    set(hImg, 'CData', gridFR_sm);
end

% Update target scatter
if ~isempty(tgt_xy)
    set(hTgt,'XData',tgt_xy(:,1),'YData',tgt_xy(:,2));
else
    set(hTgt,'XData',nan,'YData',nan);
end

% Update fit overlay
rf   = fig.UserData.rfFit;
rfOK = ~isempty(rf) && all(isfinite([rf.x0,rf.y0,rf.sx,rf.sy])) && ...
       rf.sx > 0 && rf.sx < 20 && rf.sy > 0 && rf.sy < 20;
if rfOK
    th = linspace(0,2*pi,200);
    set(hEll,   'XData',rf.x0+rf.sx*cos(th),'YData',rf.y0+rf.sy*sin(th));
    set(hCross, 'XData',rf.x0,'YData',rf.y0);
    set(hLbl,   'Position',[rf.x0, rf.y0-rf.sy-1.5, 0], ...
                'String',sprintf('RF (%.1f%s, %.1f%s)',rf.x0,char(176),rf.y0,char(176)), ...
                'Visible','on');
else
    set(hEll,  'XData',nan,'YData',nan);
    set(hCross,'XData',nan,'YData',nan);
    set(hLbl,  'Visible','off');
end
% XLim/YLim are fixed and were set when the axes were created.

if unitSel == -1; unitLbl = 'all'; else; unitLbl = num2str(unitSel); end
if rfOK
    titleStr = sprintf('Ch %d  Unit %s  (n=%d)   RF: (%.1f%s, %.1f%s)', ...
                       chSel, unitLbl, nRFcorrect, rf.x0,char(176),rf.y0,char(176));
else
    titleStr = sprintf('Ch %d  Unit %s  (n=%d trials)', chSel, unitLbl, nRFcorrect);
end
if ~strcmp(axHM.Title.String, titleStr)     % only touch the text if it moved
    axHM.Title.String   = titleStr;
    axHM.Title.FontSize = 10;
end

% ── Draw 16 spatial PSTHs ─────────────────────────────────────────────────
% Shared y-axis range across all 16 sectors
allMax = max(max(smMean + smSEM, [], 2));
if isnan(allMax) || allMax <= 0; allMax = 1; end
sharedYLim = [0, allMax * 1.1];

% A trial contributes to exactly one sector, so normally only that panel's
% trace changed. The shared y-limit is the one thing that couples the panels:
% when it moves, every panel needs the new limit even if its data is stale.
ylChanged      = ~isequal(sharedYLim, lastSharedYLim);
lastSharedYLim = sharedYLim;

clr = [0.2 0.5 0.9];
noXSectors = [1, 2, 3, 11, 12, 13];   % upper panel of each near/far pair
for s = 1:N_SECTORS
    if ~dirtySec(s) && ~ylChanged; continue; end
    ttl = sprintf('%s  n=%d', SECTOR_LABELS{s}, psthN(s));
    if strcmp(ttl, lastPanelTitle{s}); ttl = ''; end   % '' = leave title alone
    if ~isempty(ttl); lastPanelTitle{s} = ttl; end
    [hFillPS(s), hLinePS(s), hZeroPS(s)] = drawPSTH( ...
             axPS(s), hFillPS(s), hLinePS(s), hZeroPS(s), ...
             t_c_psth, smMean(s,:), smSEM(s,:), clr, ...
             psthN(s), SECTOR_LABELS{s}, ttl, sharedYLim, ...
             ~ismember(s, noXSectors), dirtySec(s));
end
needFullDraw = false;

% Axis labels on the two reference panels
if strcmp(alignStr, 'Visual onset')
    xlbl = 'Time from Visual onset (ms)';
else
    xlbl = 'Time from Saccade onset (ms)';
end
xlabel(axPS(15), xlbl,               'FontSize',7);  % S-far: bottom-center
ylabel(axPS(7),  'Firing Rate (Hz)', 'FontSize',7);  % W-far: left-middle

drawnow limitrate
end


% ══════════════════════════════════════════════════════════════════════════
function [hFill, hLine, hZero] = drawPSTH(ax, hFill, hLine, hZero, ...
                                          t_c, fr_mn, fr_se, clr, n, lbl, ...
                                          ttl, yl, showX, dataChanged)
% Reuse graphics objects (no cla) to avoid WebContextMenuController errors.
% Handles are passed in and returned rather than re-found with findobj on
% every call — that was 3 hierarchy searches per panel, 48 per tick.
%
% ttl == '' means the title text is unchanged; leave the text object alone.
% dataChanged == false means only the shared y-limit moved, so the trace
% itself does not need to be rewritten.

% isgraphics, not isvalid: isvalid returns TRUE for the GraphicsPlaceholder
% that gobjects() produces, so the objects would never get created.
if isempty(hFill) || ~isgraphics(hFill)
    hold(ax,'on');
    % The fill's x-vertices are constant for a given PSTH window — written
    % once here, then only YData changes per update.
    hFill = fill(ax, [t_c, fliplr(t_c)], nan(1, 2*numel(t_c)), clr, ...
                 'FaceAlpha',0.25,'EdgeColor','none','Tag','psth_fill');
    hLine = plot(ax, t_c, nan(size(t_c)), 'Color',clr,'LineWidth',1.2,'Tag','psth_line');
    hZero = plot(ax, [0 0],[0 1],'--','Color',[0.6 0.6 0.6],'LineWidth',0.8,'Tag','psth_zero');
    set(ax,'TickDir','out','FontSize',6,'Box','on','SortMethod','childorder', ...
           'XLim',[t_c(1), t_c(end)]);       % x range is fixed for this window
    t = title(ax, sprintf('%s  n=%d',lbl,n), 'FontSize',10,'FontWeight','bold');
    set(t,'Units','normalized','Position',[0.5, 1.02, 0]);
    if ~showX; set(ax,'XTickLabel',[]); end
    dataChanged = true;                       % nothing drawn yet
end

if dataChanged
    if n > 0
        % XData already correct — only the envelope and the trace move.
        set(hFill,'YData',[fr_mn+fr_se, fliplr(fr_mn-fr_se)]);
        set(hLine,'YData',fr_mn);
    else
        set(hFill,'YData',nan(1, 2*numel(t_c)));
        set(hLine,'YData',nan(size(t_c)));
    end
end
if ~isequal(hZero.YData, yl)
    set(hZero,'YData',yl);
end
if ~isequal(ax.YLim, yl)
    ylim(ax, yl);
end
if ~isempty(ttl)
    ax.Title.String = ttl;
end
end


% ══════════════════════════════════════════════════════════════════════════
function sIdx = getSectorIdx(ang, ecc, ECC_NEAR)
% Maps (angle in deg, eccentricity in deg) → sector index 1–16.
% 8 equal 45° direction sectors: secNum 1=E,2=NE,3=N,4=NW,5=W,6=SW,7=S,8=SE
% Sector boundaries at multiples of 45° offset by 22.5°.
if isnan(ang) || isnan(ecc)
    sIdx = NaN;
    return;
end
ang360 = mod(ang, 360);
secNum = floor(mod(ang360 + 22.5, 360) / 45) + 1;  % 1–8
isNear = ecc < ECC_NEAR;
% far/near index maps ordered by secNum (E,NE,N,NW,W,SW,S,SE)
far_map  = [8,  3,  2,  1,  7,  14, 15, 16];
near_map = [10, 6,  5,  4,  9,  11, 12, 13];
if isNear
    sIdx = near_map(secNum);
else
    sIdx = far_map(secNum);
end
end


% ══════════════════════════════════════════════════════════════════════════
function fitRFAndRedraw(fig, nFig)
fig.UserData.doFitRF = true;
plotJivesReceptiveField(nFig);
end


% ══════════════════════════════════════════════════════════════════════════
function fitResult = fitGaussian2D(gridFR_sm, GRID_CTRS)
% Fit an elliptical 2-D Gaussian to gridFR_sm.
% Returns struct with fields: x0, y0 (center deg), sx, sy (sigma deg), A, B.
[gxm, gym] = meshgrid(GRID_CTRS, GRID_CTRS);
z = gridFR_sm(:);  xv = gxm(:);  yv = gym(:);
valid = ~isnan(z) & z > 0;
if sum(valid) < 6
    fitResult = [];  return;
end
xv = xv(valid);  yv = yv(valid);  zv = z(valid);

[A0, idx] = max(zv);
B0 = min(zv);
x0 = xv(idx);  y0 = yv(idx);

gauss2d = @(p,x,y) p(1)*exp(-((x-p(2)).^2/(2*p(4)^2) + (y-p(3)).^2/(2*p(5)^2))) + p(6);
cost    = @(p) sum((zv - gauss2d(p, xv, yv)).^2);

p0   = [A0-B0, x0, y0, 2, 2, B0];
opts = optimset('Display','off','MaxIter',3000,'TolFun',1e-8,'TolX',1e-6);
try
    pFit     = fminsearch(cost, p0, opts);
    fitResult = struct('x0',pFit(2), 'y0',pFit(3), ...
                       'sx',abs(pFit(4)), 'sy',abs(pFit(5)), ...
                       'A',pFit(1), 'B',pFit(6));
catch
    fitResult = [];
end
end


% ══════════════════════════════════════════════════════════════════════════
function clearAllAndRedraw(fig, nFig)
% Wipe the entire trials array and all accumulators.
fig.UserData.doFullClear = true;
plotJivesReceptiveField(nFig);
end

