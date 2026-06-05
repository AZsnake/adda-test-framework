clear

Fs = 61.44e6;
Nw = 10;
Nh = 9;
Sf = -140;

% Leave empty to always choose file via GUI dialog.
% You can also set an absolute / relative path directly.
filename = '';
ANT_NUM = 1;

% Resolve input path robustly:
% 1) use as-is (absolute path or current working directory)
% 2) if relative and not found, resolve relative to this script folder
% 3) if still missing, let user pick a file
file_to_load = filename;
if isempty(strtrim(file_to_load))
    file_to_load = '';
elseif exist(file_to_load, 'file') ~= 2
    is_abs_win = ~isempty(regexp(filename, '^[A-Za-z]:[\\/]', 'once'));
    is_abs_unix = ~isempty(filename) && (filename(1) == '/' || filename(1) == '\');
    if ~(is_abs_win || is_abs_unix)
        script_dir = fileparts(mfilename('fullpath'));
        candidate = fullfile(script_dir, filename);
        if exist(candidate, 'file') == 2
            file_to_load = candidate;
        end
    end
end
if exist(file_to_load, 'file') ~= 2
    [pick_name, pick_path] = uigetfile({'*.bin', 'ADC BIN (*.bin)'; '*.*', 'All files'}, ...
        'Select ADC capture file');
    if isequal(pick_name, 0)
        error('Input data file not found: %s', filename);
    end
    file_to_load = fullfile(pick_path, pick_name);
end

% Input: int16 .bin from Python MATLAB BIN export / legacy BIN.
[~, ~, ext] = fileparts(file_to_load);
if ~strcmpi(ext, '.bin')
    error('Only .bin is supported. Selected file: %s', file_to_load);
end
[fid, msg] = fopen(file_to_load, 'rb');
if fid < 0
    error('Cannot open input file: %s\n%s', file_to_load, msg);
end
data = fread(fid,'int16');
fclose(fid);

data = data/2^2;
if (length(data) < 65536)
    if ANT_NUM == 2
        a = data(1:4:end);
        b = data(2:4:end);
    else
        b = data(1:2:end);
        a = data(2:2:end);
    end
else
    if ANT_NUM == 2
        a = data(1:4:65536);
        b = data(2:4:65536);
    else
        a = data(1:2:65536);
        b = data(2:2:65536);
    end
end

N = length(a);
plot(1:N, a, 'r', 1:N, b, 'g');

N = 2^floor(log(N)/log(2));

s = (a(1:N) - mean(a(1:N))) / N;

% Keep the original Hann window behavior, but be robust across MATLAB setups
% where `hanning` may be unavailable.
if exist('hanning', 'file') == 2
    win = hanning(N);
elseif exist('hann', 'file') == 2
    win = hann(N);
else
    if N <= 1
        win = ones(N, 1);
    else
        k = (0:N-1).';
        win = 0.5 - 0.5 * cos(2*pi*k/(N-1));
    end
end
s = s .* win;

af = abs(fft(s, N));
af = af(1:N/2);

for i = 1:N/2
    freq(i) = i/N*Fs;
    if (af(i) < 1e-30) af(i) = 1e-30; end
end

adb = 20 * log10(af);
[amax, ind0] = max(adb(2:end));
ind0 = ind0 + 1;
adb = adb - amax;

for i = 1:N/2
    if (adb(i) < Sf) adb(i) = Sf; end
end

dcBins = 2;

plot(freq, adb)
hold on
Npeak = 5;
adb_tmp = adb;
for k = 1:Npeak
    [pk, idx] = max(adb_tmp(dcBins:end));
    idx = idx + dcBins - 1;
    plot(freq(idx), adb(idx), 'rv', 'MarkerSize', 8, 'MarkerFaceColor', 'r')
    text(freq(idx), adb(idx)+3, sprintf('%.2fMHz\n%.1fdB', freq(idx)/1e6, adb(idx)), ...
        'HorizontalAlignment', 'center', 'FontSize', 8)
    rmStart = max(1, idx-Nw);
    rmEnd = min(N/2, idx+Nw);
    adb_tmp(rmStart:rmEnd) = -200;
end
hold off
grid on
xlabel('Frequency (Hz)')
ylabel('Amplitude (dB)')
title('FFT Spectrum')

ap = af .* af;

sigStart = max(dcBins, ind0 - Nw);
sigEnd = min(N/2, ind0 + Nw);
sp = sum(ap(sigStart:sigEnd));
adb(sigStart:sigEnd) = -180;

for i = 2:Nh
    h(i) = Sf;
end

ind(1) = ind0;
for i = 2:Nh
    hb = ind0 * i;
    while (hb > N) hb = hb - N; end
    if (hb > N/2) hb = N - hb; end
    if (hb < 1) hb = 1; end
    ind(i) = hb;

    hStart = max(1, hb - Nw - i + 1);
    hEnd = min(N/2, hb + Nw + i - 1);
    hPeak = Sf;
    for k = hStart:hEnd
        if (adb(k) > hPeak) hPeak = adb(k); end
    end

    overlap = false;
    for j = 1:i-1
        if (abs(ind(j) - hb) < Nw + i - 1)
            overlap = true;
            break;
        end
    end
    if overlap
        h(i) = Sf;
    else
        h(i) = hPeak;
    end
end

THD = 0;
for i = 2:Nh
    THD = THD + 10^(h(i)/10);
end
THD = 10*log10(THD)

totalPower = sum(ap(dcBins:N/2));
np = totalPower - sp;
SINAD = 10*log10(sp/np)

sinadInv = 10^(-SINAD/10);
thdInv = 10^(THD/10);
if (sinadInv > thdInv && sinadInv > 0)
    SNR = -10*log10(sinadInv - thdInv)
else
    SNR = SINAD
end

spurPeak = 0;
for i = dcBins:N/2
    if (i < sigStart || i > sigEnd)
        if (ap(i) > spurPeak) spurPeak = ap(i); end
    end
end
SFDR = 10*log10(sp/spurPeak)

ENOB = (SNR - 1.76) / 6.02
