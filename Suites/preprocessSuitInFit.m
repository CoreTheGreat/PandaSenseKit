function output = preprocessSuitInFit(csi,s)
%% Input validation
%   - The parameters have been validated in preprocess()
%   - Only validating the suit name whether it is 'InFit'
%
%   Input format:
%   csi - a complex matrix with size of [packetNum, subcarrierNum*links]
%   s - a struct of processing suite
assert(contains(s.suite,'InFit','IgnoreCase',true),'The suite of preprocessSuitInFit() should be InFit');

%% Conjugate multiplication for phase calibration
if contains(s.device,'iwl5300','IgnoreCase',true)
    subCarrierNum = 30;
end
csiCM = Phase_Calibration_ConjuMulti(csi,subCarrierNum);
if isempty(csiCM)
    csiCM = csi;
end

%% Noise Filtering using Butterworth Filter
if contains(s.filter,'bpf')
    csiFilter = BPF(csiCM,s.fc,s.fs); % Band-pass filter
elseif contains(s.filter,'lpf')
    csiFilter = LPF(csiCM,s.fc,s.fs); % Low-pass filter
elseif contains(s.filter,'hpf')
    csiFilter = HPF(csiCM,s.fc,s.fs); % High-pass filter
end

%% PCA-based denoising
lenChunk = floor(s.FS*s.WINPCA);
totalLength = length(csiFilter); % Total length of received signal
numChunk = floor( totalLength / lenChunk); % The number of chunks, the last one won't be considered

csi_pca = zeros(numChunk*lenChunk,size(csiFilter,2));

for i = 1:numChunk
    % Create total score sequences
    chunk = csiFilter(i*lenChunk-lenChunk+1:i*lenChunk,:);       
    [~,score,~,~,~] = pca(chunk); % PCA
    csi_pca(i*lenChunk-lenChunk+1:i*lenChunk,:) = score;
end

% The algorithm above makes sure that the big window has moved to the end.
% dc_approx has no need to update
% Only ensure that numChunk*lenChunk+1 is smaller than totalLength
if numChunk*lenChunk+1 < totalLength
    chunk = csiFilter(numChunk*lenChunk+1:totalLength,:);
    if size(chunk,1) < size(chunk,2)
        % When records is shorter than feature's number
        chunk_size = size(chunk,1);
        chunk = [chunk; zeros(size(chunk,2)-size(chunk,1)+1,size(chunk,2))];
    end
    
    [~,score,~,~,~] = pca(chunk); % PCA
    if exist('chunk_size','var')
        score = score(1:chunk_size,:);
    end
    
    csi_pca(numChunk*lenChunk+1:totalLength,:) = score;
end

%% Spectrogram De-noising Configuration
if s.CLEANSPEC
    sigma = 0.95;
    mdl_spec_lpf = fspecial('gaussian', s.WINSPECLPF, sigma); % Build filter
end

%% Spectrogram Generation
[s,frequency,time] = stft(csi_pca(:,1),s.FS,'Window',gausswin(s.WINSTFT),'OverlapLength',s.OVERLAP,'FFTLength',s.FS,'Centered',true);
psd = zeros(size(s)); % To store Power Spectrul Density (PSD)
for i = s.PCC
    [s,~,~] = stft(csi_pca(:,i),s.FS,'Window',gausswin(s.WINSTFT),'OverlapLength',s.OVERLAP,'FFTLength',s.FS,'Centered',true);
    
   %% Spectrogram De-noising
    if s.CLEANSPEC
        s = imfilter(s,mdl_spec_lpf); % Smoothing
    end
    
    psd = psd + abs(s) / length(s.PCC);
end

output = {psd,frequency,time};
end

