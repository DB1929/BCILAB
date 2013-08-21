function [h_old,h_new] = vis_artifacts(new,old,varargin)
% vis_artifacts(NewEEG,OldEEG,Options...)
% Display the artifact rejections done by any of the artifact cleaning functions.
%
% Keyboard Shortcuts:
%   [n] : display just the new time series
%   [o] : display just the old time series
%   [b] : display both time series super-imposed
%   [d] : display the difference between both time series
%   [+] : increase signal scale
%   [-] : decrease signal scale
%   [*] : expand time range
%   [/] : reduce time range
%   [h] : show/hide slider
%
% In:
%   NewEEG     : cleaned continuous EEG data set
%   OldEEG     : original continuous EEG data set
%   Options... : name-value pairs specifying the options, with names:
%                'YRange' : y range of the figure that is occupied by the signal plot
%                'YScaling' : distance of the channel time series from each other in std. deviations
%                'WindowLength : window length to display
%                'NewColor' : color of the new (i.e., cleaned) data
%                'OldColor' : color of the old (i.e., uncleaned) data
%                'HighpassOldData' : whether to high-pass the old data if not already done
%                'ScaleBy' : the data set according to which the display should be scaled, can be 
%                            'old' or 'new' (default: 'new')
%                'ChannelSubset' : optionally a channel subset to display
%                'TimeSubet' : optionally a time subrange to display
%                'DisplayMode' : what should be displayed: 'both', 'new', 'old', 'diff'
%                'ShowSetname' : whether to display the dataset name in the title
%                'EqualizeChannelScaling' : optionally equalize the channel scaling
%
% Notes:
%   This function is primarily meant for testing purposes and is not a particularly high-quality
%   implementation.
%
% Examples:
%  vis_artifacts(clean,raw)
%
%  % display only a subset of channels
%  vis_artifacts(clean,raw,'ChannelSubset',1:4:raw.nbchan);
%
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2010-07-06
%
%                                relies on the findjobj() function by Yair M. Altman.

% Copyright (C) Christian Kothe, SCCN, 2012, christian@sccn.ucsd.edu
%
% This program is free software; you can redistribute it and/or modify it under the terms of the GNU
% General Public License as published by the Free Software Foundation; either version 2 of the
% License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
% even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% General Public License for more details.
%
% You should have received a copy of the GNU General Public License along with this program; if not,
% write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
% USA

done_legend = false;

if nargin < 2
    old = new; 
elseif ischar(old)
    varargin = [{old} varargin];
    old = new;
end

% parse options
opts = hlp_varargin2struct(varargin, ...
    {'yrange','YRange'}, [0.05 0.95], ...       % y range of the figure occupied by the signal plot
    {'yscaling','YScaling'}, 3.5, ...           % distance of the channel time series from each other in std. deviations
    {'wndlen','WindowLength'}, 10, ...          % window length to display
    {'newcol','NewColor'}, [0 0 0.5], ...       % color of the new (i.e., cleaned) data
    {'oldcol','OldColor'}, [1 0 0], ...         % color of the old (i.e., uncleaned) data
    {'highpass_old','HighpassOldData'},true, ...% whether to high-pass the old data if not already done
    {'show_removed_portions','ShowRemovedPortions'},true, ...% whether to show removed data portions (if only one set is passed in)
    {'scale_by','ScaleBy'},'new',...            % the data set according to which the display should be scaled
    {'channel_subset','ChannelSubset'},[], ...  % optionally a channel subset to display
    {'time_subset','TimeSubset'},[],...         % optionally a time subrange to display
    {'display_mode','DisplayMode'},'both',...   % what should be displayed: 'both', 'new', 'old', 'diff'
    {'show_setname','ShowSetname'},true,...     % whether to display the dataset name in the title
    {'line_spec','LineSpec'},'-',...            % line style for plotting
    {'line_width','LineWidth'},0.5,...          % line width
    {'add_legend','AddLegend'},false,...        % add a legend
    {'equalize_channel_scaling','EqualizeChannelScaling'},false);  % optionally equalize the channel scaling

% ensure that the data are not epoched and expand the rejections with NaN's (now both should have the same size)
if opts.show_removed_portions
    new = expand_rejections(to_continuous(new));
    old = expand_rejections(to_continuous(old));
end
new.chanlocs = old.chanlocs;

% correct for filter delay
if isfield(new.etc,'filter_delay')
    new.data = new.data(:,[1+round(new.etc.filter_delay*new.srate):end end:-1:(end+1-round(new.etc.filter_delay*new.srate))]); end
if isfield(old.etc,'filter_delay')
    old.data = old.data(:,[1+round(old.etc.filter_delay*old.srate):end end:-1:(end+1-round(old.etc.filter_delay*old.srate))]); end

% make sure that the old data is high-passed the same way as the new data
if opts.highpass_old && isfield(new.etc,'clean_drifts_kernel') && ~isfield(old.etc,'clean_drifts_kernel')
    old.data = old.data';
    for c=1:old.nbchan
        old.data(:,c) = filtfilt_fast(new.etc.clean_drifts_kernel,1,old.data(:,c)); end
    old.data = old.data';
end

if isscalar(opts.line_width)
    opts.line_width = [opts.line_width opts.line_width]; end

% optionally pick a subrange to work on
if ~isempty(opts.channel_subset)
    old = pop_select(old,'channel',opts.channel_subset);
    new = pop_select(new,'channel',opts.channel_subset);
end

if ~isempty(opts.time_subset)
    old = pop_select(old,'time',opts.time_subset);
    new = pop_select(new,'time',opts.time_subset);
end

if opts.equalize_channel_scaling    
    rescale = 1./mad(old.data,[],2);
    new.data = bsxfun(@times,new.data,rescale);
    old.data = bsxfun(@times,old.data,rescale);
end

% create a unique name for this visualization and store the options it in the workspace
taken = evalin('base','whos(''vis_*'')');
visname = genvarname('vis_artifacts_opts',{taken.name});
visinfo.opts = opts;
assignin('base',visname,visinfo);

% create figure & slider
lastPos = 0;
hFig = figure('ResizeFcn',@on_window_resized,'KeyPressFcn',@(varargin)on_key(varargin{2}.Key)); hold; axis();
hAxis = gca;
hSlider = uicontrol('style','slider','KeyPressFcn',@(varargin)on_key(varargin{2}.Key)); on_resize();
jSlider = findjobj(hSlider);
jSlider.AdjustmentValueChangedCallback = @on_update;

% do the initial update
on_update();


    function repaint(relPos,moved)
        % repaint the current data
        
        % if this happens, we are maxing out MATLAB's graphics pipeline: let it catch up
        if relPos == lastPos && moved
            return; end
        
        % get potentially updated options
        visinfo = evalin('base',visname);
                
        % axes
        cla;
        
        % compute pixel range from axis properties
        xl = get(hAxis,'XLim');
        yl = get(hAxis,'YLim');
        fp = get(hFig,'Position');
        ap = get(hAxis,'Position');
        pixels = (fp(3))*(ap(3)-ap(1));
        ylr = yl(1) + opts.yrange*(yl(2)-yl(1));
        channel_y = (ylr(2):(ylr(1)-ylr(2))/(size(new.data,1)-1):ylr(1))';
        
        % compute sample range
        wndsamples = visinfo.opts.wndlen * new.srate;
        pos = floor((size(new.data,2)-wndsamples)*relPos);
        wndindices = 1 + floor(0:wndsamples/pixels:(wndsamples-1));
        wndrange = pos+wndindices;
        
        oldwnd = old.data(:,wndrange);
        newwnd = new.data(:,wndrange);
        if strcmp(opts.scale_by,'old')
            iqrange = iqr(oldwnd')';
        else
            iqrange = iqr(newwnd')';
            iqrange(isnan(iqrange)) = iqr(oldwnd(isnan(iqrange),:)')';
        end
        scale = ((ylr(2)-ylr(1))/size(new.data,1)) ./ (visinfo.opts.yscaling*iqrange); scale(~isfinite(scale)) = 0;
        scale(scale>median(scale)*3) = median(scale);
        scale = repmat(scale,1,length(wndindices));
                
        % draw
        if opts.show_setname
            tit = sprintf('%s - ',[old.filepath filesep old.filename]);
        else
            tit = '';
        end
        
        if ~isempty(wndrange)
            tit = [tit sprintf('[%.1f - %.1f]',new.xmin + (wndrange(1)-1)/new.srate, new.xmin + (wndrange(end)-1)/new.srate)];        
        end
        
        switch visinfo.opts.display_mode            
            case 'both'                
                title([tit '; superposition'],'Interpreter','none');
                h_old = plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*oldwnd)','Color',opts.oldcol,'LineWidth',opts.line_width(1));
                h_new = plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*newwnd)','Color',opts.newcol,'LineWidth',opts.line_width(2));
            case 'new'
                title([tit '; cleaned'],'Interpreter','none');
                plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*newwnd)','Color',opts.newcol,'LineWidth',opts.line_width(2));
            case 'old'
                title([tit '; original'],'Interpreter','none');
                plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*oldwnd)','Color',opts.oldcol,'LineWidth',opts.line_width(1));
            case 'diff'
                title([tit '; difference'],'Interpreter','none');
                plot(xl(1):(xl(2)-xl(1))/(length(wndindices)-1):xl(2), (repmat(channel_y,1,length(wndindices)) + scale.*(oldwnd-newwnd))','Color',opts.newcol,'LineWidth',opts.line_width(1));
        end
        axis([0 1 0 1]);
        
        if opts.add_legend && ~done_legend
            legend([h_old(1);h_new(1)],'Original','Corrected');
            done_legend = 1;
        end
        drawnow;


        lastPos = relPos;
    end


    function on_update(varargin)
        % slider moved
        repaint(get(hSlider,'Value'),~isempty(varargin));
    end

    function on_resize(varargin)
        % adapt/set the slider's size
        wPos = get(hFig,'Position');
        if ~isempty(hSlider)
            try
                set(hSlider,'Position',[20,20,wPos(3)-40,20]);
            catch,end
            on_update;
        end
    end

    function on_window_resized(varargin)
        % window resized
        on_resize();
    end

    function EEG = to_continuous(EEG)
        % convert an EEG set to continuous if currently epoched
        if ndims(EEG.data) == 3
            EEG.data = EEG.data(:,:);
            [EEG.nbchan,EEG.pnts,EEG.trials] = size(EEG.data);
        end
    end

    function EEG = expand_rejections(EEG)
        % reformat the new data so that it can be super-imposed with the old data
        [EEG.nbchan,EEG.pnts] = size(EEG.data);
        if ~isfield(EEG.etc,'clean_channel_mask')
            EEG.etc.clean_channel_mask = true(1,EEG.nbchan); end
        if ~isfield(EEG.etc,'clean_sample_mask')
            EEG.etc.clean_sample_mask = true(1,EEG.pnts); end
        tmpdata = nan(length(EEG.etc.clean_channel_mask),length(EEG.etc.clean_sample_mask));
        tmpdata(EEG.etc.clean_channel_mask,EEG.etc.clean_sample_mask) = EEG.data;
        EEG.data = tmpdata;
        [EEG.nbchan,EEG.pnts] = size(EEG.data);
    end

    function on_key(key)
        visinfo = evalin('base',visname);
        switch lower(key)
            case {'add','+'}
                % decrease datascale
                visinfo.opts.yscaling = visinfo.opts.yscaling*0.9;
            case {'subtract','-'}
                % increase datascale
                visinfo.opts.yscaling = visinfo.opts.yscaling*1.1;
            case {'multiply','*'}
                % increase timerange
                visinfo.opts.wndlen = visinfo.opts.wndlen*1.1;                
            case {'divide','/'}
                % decrease timerange
                visinfo.opts.wndlen = visinfo.opts.wndlen*0.9;                
            case 'pagedown'
                % shift display page offset down
                visinfo.opts.pageoffset = visinfo.opts.pageoffset+1;                
            case 'pageup'
                % shift display page offset up
                visinfo.opts.pageoffset = visinfo.opts.pageoffset-1;
            case 'n'
                visinfo.opts.display_mode = 'new';
            case 'o'
                visinfo.opts.display_mode = 'old';
            case 'b'
                visinfo.opts.display_mode = 'both';
            case 'd'
                visinfo.opts.display_mode = 'diff';
            case 'h'
                if strcmp(get(hSlider,'Visible'),'on')
                    set(hSlider,'Visible','off')
                else
                    set(hSlider,'Visible','on')
                end
        end        
        assignin('base',visname,visinfo);
        on_update();
    end
end