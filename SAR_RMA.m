clear all;
clc;

% Defining constants
[y, fs] = audioread('SAR_Test_File.m4a');
c = 299792458;
fc = 2.45e9; % center frequency
f_start = 2.4e9;
f_stop = 2.5e9;
BW = f_stop - f_start;
Ts = 0.02;
Trp = 0.250;
Ns = fs*Ts;
Nrp = fs*Trp;

% Labeling data
data = -y(:,1);
trig = -y(:,2);

% Identify range profile acquisition and parse data and sync signal
rp_start = abs(trig) > mean(abs(trig));
count = 0;
RP = [];
RP_trig = [];
for i = Nrp+1:(size(rp_start,1) - Nrp)
    if rp_start(i) == 1 && sum(rp_start(i-Nrp:i-1)) == 0
        count = count + 1;
        RP(count,:) = data(i:i+Nrp-1);
        RP_trig(count,:) = trig(i:i+Nrp-1);
    end
end

% Parse data according to rising edge trigger
thresh = 0.08;
for j = 1:size(RP,1)
    clear SIF;
    SIF = zeros(Ns,1);
    start = (RP_trig(j,:) > thresh);
    count = 0;
    for i = 12:(size(start,2) - 2*Ns)
        [Y, I] = max(start(1,i:i+2*Ns));
        if mean(start(i-10:i-2)) == 0 && I == 1
            count = count + 1;
            SIF = RP(j,i:i+Ns-1)' + SIF;
        end
    end
    SI = SIF/count;
    FF = ifft(SI);
    clear SI;
    sif(j,:) = fft(FF(size(FF,1)/2+1:size(FF,1)));
end

% Replace NaN with 1e-30 in sif
[row, column] = size(sif);
for m = 1:row
    for n = 1:column
        if isnan(sif(m,n))
            sif(m,n) = 1e-30;
        end
    end
end

% Define more constants
cr = BW/Ts;
Rs = 0;
lambda = c/fc;
delta_x = lambda/2;
L = delta_x*(size(sif,1));
Xa = linspace(-L/2, L/2, (L/delta_x));
time = linspace(0, Ts, size(sif,2));
Kr = linspace(((4*pi/c)*(fc - BW/2)), ((4*pi/c)*(fc + BW/2)), (size(time,2)));

for j = 1:size(sif,1)
    sif(j,:) = sif(j,:) - mean(sif,1);
end

% Mean subtraction for ground clutter reduction
%Clear N;
N = size(sif,2);
H = [];
for i = 1:N
    H(i) = 0.5 + 0.5*cos(2*pi*(i-N/2)/N);
end

% Hanning window
sif_h = [];
for i = 1:size(sif,1)
    sif_h(i,:) = sif(i,:).*H;
end
sif = sif_h;

% Plot the phase before along track FFT
fig_count = 1;
figure(fig_count);
S_image = angle(sif);
imagesc(Kr, Xa, S_image);
colormap('default');
xlabel('K_r(rad/m)');
ylabel('SAR Position, Xa(m)');
colorbar;
fig_count = fig_count + 1;

% Cross range Fourier transform
zpad = 2048;
s_zeros = zeros(zpad, size(sif,2));
for i = 1:size(sif,2)
    index = round((zpad-size(sif,1))/2);
    s_zeros(index+1:(index + size(sif,1)),i) = sif(:,i);
end
sif = s_zeros;
S = fftshift(fft(sif, [], 1), 1);
Kx = linspace((-pi/delta_x), (pi/delta_x), (size(S,1)));

% Plot the magnitude after along track FFT
figure(fig_count);
S_image = 20*log10(abs(S));
imagesc(Kr, Kx, S_image, [max(max(S_image))-40, max(max(S_image))]);
colormap('default');
xlabel('K_r(rad/m)');
ylabel('K_x(rad/m)');
colorbar;
fig_count = fig_count+ 1;

%Plot the phase after long track FFT
figure(fig_count);
S_image = angle(S);
imagesc(Kr, Kx, S_image);
colormap('default');
xlabel('K_r(rad/m)');
ylabel('K_x(rad/m)');
colorbar;
fig_count = fig_count+ 1;

% Matched filter
% Rs = 0, already set earlier
S_matched = S;

% Stolt Interpolation
kstart = floor(min(Kr) - 20); % Can be set according to filled area of Ky
kstop = ceil(max(Kr)); % Can be set according to filled area of Ky
Ky_e = linspace(kstart,kstop,1024);
count = 0;
Ky = [];
S_st = [];
for ii = 1:zpad
    count = count + 1;
    Ky(count,:) = sqrt(Kr.^2 -Kx(ii)^2);
    S_st(count,:) = (interp1(Ky(count,:), S_matched(ii,:), Ky_e));
end

% Replace NaN with 1e-30 in S_st
% S_st(find(isnan(S_st))) = 1e-30;, matlab does not like find function
[row, column] = size(S_st);
for m = 1:row
    for n = 1:column
        if isnan(S_st(m,n))
            S_st(m,n) = 1e-30;
        end
    end
end

% Plot the phase after Stolt interpolation
figure(fig_count);
S_image = angle(S_st);
imagesc(Ky_e, Kx, S_image);
colormap('default');
xlabel('K_y(rad/m)');
ylabel('K_x(rad/m)');
colorbar;
fig_count = fig_count + 1;

% Inverse 2D FFT to image domain
v = ifft2(S_st,(size(S_st,1)*4),(size(S_st,2)*4));

% Plot final image
bw = c*(kstop-kstart)/(4*pi);
max_range = (c*size(S_st,2)/(2*bw));
figure(fig_count);
S_image = v;
S_image = fliplr(rot90(S_image));
cr1 = -25; % depends on the Kx of the Stolt Interpolation
cr2 = 25; % depends on the Kx of the Stolt Interpolation
dr1 = 1;
dr2 = 100;

% Truncate data
dr_index1 = round((dr1/max_range)*size(S_image,1));
dr_index2 = round((dr2/max_range)*size(S_image,1));
cr_index1 = round(((cr1+zpad*delta_x/(2*1))/(zpad*delta_x/1))*size(S_image,2));
cr_index2 = round(((cr2+zpad*delta_x/(2*1))/(zpad*delta_x/1))*size(S_image,2));
trunc_image = S_image(dr_index1:dr_index2,cr_index1:cr_index2);
downrange = linspace(-1*dr1,-1*dr2,size(trunc_image,1));
crossrange = linspace(cr1, cr2, size(trunc_image, 2));
for ii = 1:size(trunc_image,2)
trunc_image(:,ii) = (trunc_image(:,ii)').*(abs(downrange*1)).^(3/2);
end
trunc_image= 20*log10(abs(trunc_image));
imagesc(crossrange, downrange, trunc_image, [max(max(trunc_image))-40, max(max(trunc_image))-0]);
colormap('default');
axis equal;
colorbar;






