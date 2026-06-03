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

global trials

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

% Sector labels in axPS index order (1–16)
SECTOR_LABELS = {'NW-far','N-far','NE-far', ...
                 'NW-near','N-near','NE-near', ...
                 'W-far','E-far','W-near','E-near', ...
                 'SW-near','S-near','SE-near', ...
                 'SW-far','S-far','SE-far'};
N_SECTORS = 16;

% ── Persistent state ──────────────────────────────────────────────────────
persistent fig hChDD hUnitDD hRFt0 hRFt1 hPSTHt0 hPSTHt1 hAlignDD ...
           axHM axPS ...
           lastNCh lastNUnits ...
           gridFR gridN nRFcorrect lastRFTrial lastRFch lastRFunitSel lastRFwin lastRFalign ...
           tgt_xy lastTgtTrial ...
           psthN psthMean psthM2 ...
           lastPSTHTrial lastPSTHch lastPSTHunitSel lastPSTHwin lastPSTHalign

if isempty(trials); return; end

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
    fig.UserData = struct('doClear', false);
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
    hChDD = uicontrol(fig,'Style','popupmenu','Units','pixels', ...
        'Position',[54 ye 80 22],'String',arrayfun(@num2str,1:96,'uni',0), ...
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

    % Clear button
    uicontrol(fig,'Style','pushbutton','Units','pixels', ...
        'Position',[935 ye 60 22],'String','Clear', ...
        'FontSize',10,'BackgroundColor',[0.9 0.7 0.7], ...
        'Callback',@(~,~) clearAndRedraw(fig, nFig));

    % Plot area — manual axes so every PSTH panel has identical dimensions
    pPlot = uipanel(fig,'Units','normalized','Position',[0,0,1,fd], ...
                    'BorderType','none','BackgroundColor',get(fig,'Color'));

    % Layout constants (normalized within pPlot, y=0 at bottom)
    pw = 0.125;  ph = 0.135;   % panel width / height — same for all 16 PSTH axes
    gx = 0.010;  gy = 0.012;   % horizontal / vertical gap
    lm = 0.065;  rm = 0.010;
    bm = 0.050;  tm = 0.020;

    % 5 vertical row positions (bottom edge of each panel row)
    y5 = bm;                          % SW-far / S-far / SE-far  (bottom)
    y4 = y5 + ph + gy;                % SW-near / S-near / SE-near
    y3 = y4 + ph + gy;                % heatmap bottom edge
    hmh = 2*ph + gy;                  % heatmap height = 2 panel heights
    y2 = y3 + hmh + 3*gy;            % NW-near / N-near / NE-near (extra gap clears heatmap title)
    y1 = y2 + ph + gy;               % NW-far / N-far / NE-far  (top)
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
end

% ── Refresh channel/unit dropdowns ────────────────────────────────────────
if ~isempty(trials(end).spike_times)
    nCh = size(trials(end).spike_times, 1);
    if isempty(lastNCh) || lastNCh ~= nCh
        hChDD.String = arrayfun(@num2str, 1:nCh, 'uni', 0);
        hChDD.Value  = min(chSel, nCh);
        chSel        = hChDD.Value;
        lastNCh      = nCh;
    end
    nSortedUnits = max(0, size(trials(end).spike_times, 2) - 2);
    if isempty(lastNUnits) || lastNUnits ~= nSortedUnits
        unitStrs = [arrayfun(@num2str, 1:nSortedUnits, 'uni', 0), {'all'}];
        hUnitDD.String = unitStrs;
        hUnitDD.Value  = min(hUnitDD.Value, numel(unitStrs));
        lastNUnits = nSortedUnits;
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
forceClear = isfield(fig.UserData, 'doClear') && fig.UserData.doClear;
if forceClear; fig.UserData.doClear = false; end

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

% ── Reset RF accumulators ─────────────────────────────────────────────────
nG = numel(GRID_EDGES) - 1;
if rfChanged || isempty(gridFR)
    gridFR        = nan(nG, nG);
    gridN         = zeros(nG, nG);
    nRFcorrect    = 0;
    tgt_xy        = [];
    lastRFch      = chSel;
    lastRFunitSel = unitSel;
    lastRFwin     = rfWin;
    lastRFalign   = alignStr;
    if forceClear
        rfStart      = nTrials + 1;   % skip all existing trials
        lastRFTrial  = nTrials;
        lastTgtTrial = nTrials;
    else
        rfStart      = 1;
        lastRFTrial  = 0;
        lastTgtTrial = 0;
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
        psthStart     = nTrials + 1;  % skip all existing trials
        lastPSTHTrial = nTrials;
    else
        psthStart     = 1;
        lastPSTHTrial = 0;
    end
else
    psthStart = lastPSTHTrial + 1;
end

winSec = rfWin / 1000;
winDur = diff(rfWin) / 1000;

% ── Incremental accumulation ─────────────────────────────────────────────
loopStart = min(rfStart, psthStart);

for n = loopStart : nTrials
    correct = ischar(trials(n).Trialoutcome) && ...
              contains(trials(n).Trialoutcome, 'correct');
    sp = trials(n).spike_times;
    if isempty(sp) || chSel > size(sp, 1); continue; end

    % Build single merged spike vector for this trial
    if unitSel == -1
        allSpks = [];
        for u = 3 : size(sp, 2)
            if ~isempty(sp{chSel, u})
                allSpks = [allSpks; sp{chSel, u}(:)]; %#ok<AGROW>
            end
        end
        allSpks = sort(allSpks);
    else
        u = 2 + unitSel;
        if u <= size(sp, 2) && ~isempty(sp{chSel, u})
            allSpks = sp{chSel, u}(:);
        else
            allSpks = zeros(0, 1);
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

% ── Draw heatmap ──────────────────────────────────────────────────────────
cla(axHM); hold(axHM,'on');
imagesc(axHM, GRID_CTRS, GRID_CTRS, gridFR_sm);
axis(axHM, [-20 20 -20 20]); axis(axHM,'equal'); axis(axHM,'square');
if ~isempty(tgt_xy)
    scatter(axHM, tgt_xy(:,1), tgt_xy(:,2), 60, 'w','o','LineWidth',1.5);
end
scatter(axHM, 0, 0, 30, FIX_COLOR, 'filled');
if unitSel == -1; unitLbl = 'all'; else; unitLbl = num2str(unitSel); end
title(axHM, sprintf('Ch %d  Unit %s  (n=%d trials)', chSel, unitLbl, nRFcorrect), ...
      'FontSize',10);
colormap(axHM, 'parula');
set(axHM, 'YDir','normal','XTick',[],'YTick',[]);
box(axHM,'on');
cb = colorbar(axHM, 'Location','eastoutside','FontSize',7);
cb.Label.String = 'FR (sp/s)';
cb.Label.FontSize = 7;

% ── Draw 16 spatial PSTHs ─────────────────────────────────────────────────
% Sectors in col 1 (leftmost axis per row): NW-far, NW-near, W-far, SW-near, SW-far
leftSectors   = [1, 4, 7, 11, 14];
% Sectors in row 6 (bottom axis per col): SW-far, S-far, SE-far
bottomSectors = [14, 15, 16];

% Shared y-axis range across all 16 sectors
allMax = max(max(smMean + smSEM, [], 2));
if isnan(allMax) || allMax <= 0; allMax = 1; end
sharedYLim = [0, allMax * 1.1];

clr = [0.2 0.5 0.9];
for s = 1:N_SECTORS
    drawPSTH(axPS(s), t_c_psth, smMean(s,:), smSEM(s,:), clr, ...
             psthN(s), SECTOR_LABELS{s}, sharedYLim, ...
             ismember(s, bottomSectors), ismember(s, leftSectors));
end

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
function drawPSTH(ax, t_c, fr_mn, fr_se, clr, n, lbl, yl, showX, showY)
cla(ax); hold(ax,'on');
if n > 0
    fill(ax, [t_c, fliplr(t_c)], ...
             [fr_mn+fr_se, fliplr(fr_mn-fr_se)], ...
             clr, 'FaceAlpha',0.25, 'EdgeColor','none');
    plot(ax, t_c, fr_mn, 'Color',clr, 'LineWidth',1.2);
end
plot(ax, [0 0], yl, '--', 'Color',[0.6 0.6 0.6], 'LineWidth',0.8);
xlim(ax, [t_c(1), t_c(end)]);
ylim(ax, yl);
title(ax, sprintf('%s  n=%d', lbl, n), 'FontSize',7, 'FontWeight','normal');
set(ax, 'TickDir','out','FontSize',6,'Box','on');
if ~showX; set(ax, 'XTickLabel',[]); end
if ~showY; set(ax, 'YTickLabel',[]); end
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
function clearAndRedraw(fig, nFig)
fig.UserData.doClear = true;
plotJivesReceptiveField(nFig);
end

