function [specslope,spec] = bz_PowerSpectrumSlope(lfp,winsize,dt,varargin)
%[specslope,spec] = bz_PowerSpectrumSlope(lfp,winsize,dt) calculates the
%slope of the power spectrum, a metric of cortical state and E/I balance
%see Gao, Peterson, Voytek 2016;  Waston, Ding, Buzsaki 2017
%
%INPUTS
%   lfp         a buzcode-formatted lfp structure (use bz_GetLFP)
%               needs fields: lfp.data, lfp.timestamps, lfp.samplingRate
%   winsize     size of the silding time window (s, 2-4 recommended)
%   dt          sliding time interval (s)
%
%   (optional)
%       'frange'    (default: [4 100])
%       'channels'  subset of channels to calculate PowerSpectrumSlope
%                   (default: all)
%       'showfig'   true/false - show a summary figure of the results
%                   (default:false)
%       'saveMat'   put your basePath here to save/load
%                   baseName.PowerSpectrumSlope.lfp.mat  (default: false)
%       'Redetect'  (default: false) to force redetection even if saved
%                   file exists
%
%OUTPUTS
%   specslope
%       .data
%       .timestamps
%       .intercept
%   specgram
%       .data       complex-valued spectrogram
%       .timestamps
%       .amp        log10-transformed amplitude of the spectrogram
%
%
%DLevenstein 2018
%%
p = inputParser;
addParameter(p,'showfig',false,@islogical)
addParameter(p,'saveMat',false)
addParameter(p,'channels',[])
addParameter(p,'frange',[4 100])
addParameter(p,'Redetect',false)
parse(p,varargin{:})
SHOWFIG = p.Results.showfig;
saveMat = p.Results.saveMat;
channels = p.Results.channels;
frange = p.Results.frange;
REDETECT = p.Results.Redetect;


%%
if saveMat
    basePath = saveMat;
    baseName = bz_BasenameFromBasepath(basePath);
    savename = fullfile(basePath,[baseName,'.PowerSpectrumSlope.lfp.mat']);
    
    if exist(savename,'file') && ~REDETECT
        load(savename)
        return
    end
end

%% For multiple lfp channels
if ~isempty(channels)
    usechans = ismember(lfp.channels,channels);
    lfp.data = lfp.data(:,usechans);
    lfp.channels = lfp.channels(usechans);
elseif ~isfield(lfp,'channels')
    lfp.channels = nan;
end

if length(lfp.channels)>1
  %loop each channel and put the stuff in the right place
	for cc = 1:length(lfp.channels)
        if mod(cc,4)==1
            display([num2str(cc),' of ',...
                num2str(length(lfp.channels)),' complete!'])
        end
        lfp_temp = lfp; 
        lfp_temp.data = lfp_temp.data(:,cc); 
        lfp_temp.channels = lfp_temp.channels(cc);
        specslope_temp = bz_PowerSpectrumSlope(lfp_temp,winsize,dt,varargin{:});
        
        if ~exist('specslope','var')
            specslope = specslope_temp;
            %Don't save the big stuff for multiple channels.
            specslope.resid = [];
        else
            specslope.data(:,cc) = specslope_temp.data;
            specslope.intercept(:,cc) = specslope_temp.intercept;
            specslope.rsq(:,cc) = specslope_temp.rsq;
            specslope.specgram(:,:,cc) = specslope_temp.specgram;
        end
        
	end
    specslope.channels = lfp.channels;
    return
end
%%
%Calcluate spectrogram
noverlap = winsize-dt;
spec.freqs = logspace(log10(frange(1)),log10(frange(2)),200);
winsize_sf = round(winsize .*lfp.samplingRate);
noverlap_sf = round(noverlap.*lfp.samplingRate);
[spec.data,~,spec.timestamps] = spectrogram(single(lfp.data),winsize_sf,noverlap_sf,spec.freqs,lfp.samplingRate);

spec.amp = log10(abs(spec.data));

%% Fit the slope of the power spectrogram
rsq = zeros(size(spec.timestamps));
s = zeros(length(spec.timestamps),2);
yresid = zeros(length(spec.timestamps),length(spec.freqs));
for tt = 1:length(spec.timestamps)
    %Fit the line
    x = log10(spec.freqs);  y=spec.amp(:,tt)';
    s(tt,:) = polyfit(x,y,1);
    %Calculate the residuals
    yfit =  s(tt,1) * x + s(tt,2);
    yresid(tt,:) = y - yfit;
    %Calculate the rsquared value
    SSresid = sum(yresid(tt,:).^2);
    SStotal = (length(y)-1) * var(y);
    rsq(tt) = 1 - SSresid/SStotal;
end

%% Output Structure
specslope.data = s(:,1);
specslope.intercept = s(:,2);
specslope.timestamps = spec.timestamps';
specslope.specgram = spec.amp;
specslope.samplingRate = 1./dt;

specslope.detectionparms.winsize = winsize;
specslope.detectionparms.frange = frange;

specslope.rsq = rsq';
specslope.resid = yresid;
specslope.freqs = spec.freqs;

specslope.channels = lfp.channels;

if saveMat
    save(savename,'specslope','spec');
end

%% Figure
if SHOWFIG
    
    bigsamplewin = bz_RandomWindowInIntervals(spec.timestamps([1 end]),30);

   %hist(specslope.data,10)
   specmean.all = mean(spec.amp,2);
   slopebinIDs = discretize(specslope.data,linspace(min(specslope.data),max(specslope.data),6));
   for bb = 1:length(unique(slopebinIDs))
        specmean.bins(bb,:) = mean(spec.amp(:,slopebinIDs==bb),2);
        
        exwin(bb,:) = spec.timestamps(randsample(find(slopebinIDs==bb),1))+(winsize.*[-0.5 0.5]);
   end
figure
    subplot(4,1,1)
        imagesc(spec.timestamps,log2(spec.freqs),spec.amp)
        LogScale('y',2)
        ylabel('f (Hz)')
        axis xy
        xlim(bigsamplewin)
        bz_ScaleBar('s')
    subplot(8,1,3)
        plot(lfp.timestamps,lfp.data,'k')
        axis tight
        box off
        xlim(bigsamplewin)
        lfprange = get(gca,'ylim');
        set(gca,'XTickLabel',[])
        ylabel('LFP')
    subplot(8,1,4)
        plot(specslope.timestamps,specslope.data,'k')
        axis tight
        box off
        xlim(bigsamplewin)
        set(gca,'XTickLabel',[])
         
    subplot(6,2,7)
        hist(specslope.data,10)
        box off
        xlabel('PSS')
        
        
    subplot(3,3,7)
        plot(log2(spec.freqs),specmean.all,'k','linewidth',2)
        hold on
        plot(log2(spec.freqs),specmean.bins,'k')
        LogScale('x',2)
        axis tight
        box off
        
    for bb = 1:2:5    
	subplot(6,2,12-(bb-1))
        plot(lfp.timestamps,lfp.data,'k')
        axis tight
        box off
        xlim(exwin(bb,:)');ylim(lfprange)
        set(gca,'XTickLabel',[])
        set(gca,'YTick',[])
        ylabel('LFP')
    end
        bz_ScaleBar('s')

if saveMat
    figfolder = [basePath,filesep,'DetectionFigures'];
    NiceSave('PowerSpectrumSlope',figfolder,baseName)
end
        
end


end

