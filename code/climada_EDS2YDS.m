function YDS=climada_EDS2YDS(EDS,hazard)
% climada template
% MODULE:
%   core
% NAME:
%   climada_EDS2YDS
% PURPOSE:
%   convert an event (per occurrence) damage set (EDS) into a year damage
%   set (YDS), making reference to hazard.orig_yearset (if exists).
%
%   The code does perform some consistency checks, but the user is
%   ultimately repsonsible for results ;-)
%
%   Note that for TS and TR, the TC hazard event set contains
%   hazard.orig_yearset, not each sub-peril hazard event set might contain
%   its own yearset. See climada_tc_hazard_set for a good example of how
%   such an hazard.orig_yearset is constructed.
% CALLING SEQUENCE:
%   YDS=climada_EDS2YDS(EDS,hazard)
% EXAMPLE:
%   YDS=climada_EDS2YDS(climada_EDS_calc('',hazard),hazard)
% INPUTS:
%   EDS: an event damage set (EDS), as produced by climada_EDS_calc 
%       (see there)
% OPTIONAL INPUT PARAMETERS:
%   hazard: a hazard event set (either a struct or a full filename with
%       path) which contains a yearset in hazard.orig_yearset
%       Note that for TS and TR, the TC hazard event set contains
%       hazard.orig_yearset, not each sub-peril hazard event set
%       If empty, the hazard event set is inferred from
%       EDS.annotation_name, which often contains the filename (without
%       path) of the hazard event set. If this is the case, this hazard is
%       used, if not, the function prompts for the hazard event set to use.
% OUTPUTS:
%   YDS: the year damage set (YDS), a struct with same fields as EDS (such
%       as Value, ED, ...) plus yyyy and orig_year_flag. All fields same
%       content as in EDS, except:
%       yyyy(i): the year i
%       damage(i): the sum of damage for year(i). Note that for a
%           probabilitic hazard event set, there are ens_size+1 same years, 
%           the first instance being the original year.
%       frequency(i): the annual frequency, =1
%       orig_year_flag(i): =1 if year i is an original year, =0 else
%       Hint: if you want to staore a YDS back into an EDS, note that there
%       are two more fields in YDS than EDS: yyyy and orig_year_flag
% MODIFICATION HISTORY:
% David N. Bresch, david.bresch@gmail.com, 20141226, initial
% David N. Bresch, david.bresch@gmail.com, 20150116, YDS fields same order as in EDS
% David N. Bresch, david.bresch@gmail.com, 20150204, automatic hazard set detection
%-

YDS=[]; % init output

global climada_global
if ~climada_init_vars,return;end % init/import global variables

%%if climada_global.verbose_mode,fprintf('*** %s ***\n',mfilename);end % show routine name on stdout

% poor man's version to check arguments
% and to set default value where  appropriate
if ~exist('EDS','var'),return;end
if ~exist('hazard','var'),hazard=[];end

% PARAMETERS
%

if isempty(hazard) % try to infer from EDS
    hazard_file=[climada_global.data_dir filesep 'hazards' filesep strtok(EDS.annotation_name) '.mat'];
    if exist(hazard_file,'file'),load(hazard_file);end % if it fails, hazard remains empty
end % isempty(hazard)

% prompt for hazard if not given
if isempty(hazard) % local GUI
    hazard_set_file=[climada_global.data_dir filesep 'hazards' filesep '*.mat'];
    [filename, pathname] = uigetfile(hazard_set_file, 'Select hazard event set:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        hazard_set_file=fullfile(pathname,filename);
    end
    load(hazard_set_file) % contains hazard
end

if ischar(hazard) % a filename instead of a hazard set struct passed
    hazard_set_file=hazard; clear hazard
    load(hazard_set_file) % contains hazard
end

if ~isfield(hazard,'orig_yearset')
    fprintf('Error: hazard event set does not contain orig_yearset\n')
    fprintf(' Note that for TS and TR, the TC hazard event set contains\n')
    fprintf(' hazard.orig_yearset, not each sub-peril hazard event set\n')
    return
end

% figure the probabilistic ensemble size (=0 if only original events)
n_years = length(hazard.orig_yearset);
ens_size=(hazard.event_count/hazard.orig_event_count)-1;
orig_event_mismatch_count=0; % init
prob_event_mismatch_count=0; % init

% consistency check
if abs(length(EDS.damage)-hazard.event_count)>eps
    fprintf('Error: EDS and hazard events do not match, aborted\n');
    return
end

% copy some fields from EDS to YDS:
YDS.reference_year=EDS.reference_year;
YDS.event_ID=[]; % to indicate not by event any more
YDS.damage=[]; % init, see below
if isfield(EDS,'ED_at_centroid'),YDS.ED_at_centroid=EDS.ED_at_centroid;end
YDS.Value=EDS.Value;
YDS.frequency=[]; % init, see below
YDS.orig_event_flag=[]; % to indicate not by event any more
YDS.peril_ID=EDS.peril_ID;
YDS.hazard=EDS.hazard;
YDS.comment=EDS.comment;
if isfield(EDS,'assets'),YDS.assets=EDS.assets;end
if isfield(EDS,'damagefunctions'),YDS.damagefunctions=EDS.damagefunctions;end
YDS.annotation_name=EDS.annotation_name;
YDS.ED=EDS.ED;

% template for-loop with waitbar or progress to stdout
t0       = clock;
msgstr   = sprintf('processing %i years',n_years);
mod_step = 10; % first time estimate after 10 years

if climada_global.waitbar
    fprintf('%s (updating waitbar with estimation of time remaining every 10th year)\n',msgstr);
    h        = waitbar(0,msgstr);
    set(h,'Name','Yearset');
else
    fprintf('%s (waitbar suppressed)\n',msgstr);
    format_str='%s';
end

next_damage_year=1;
for year_i=1:n_years
    
    for ens_i=0:ens_size % note: ens_i=0 is orig year
        YDS.damage(next_damage_year)=0; % init
        YDS.yyyy(next_damage_year)  =hazard.orig_yearset(year_i).yyyy;
        for event_i=1:hazard.orig_yearset(year_i).event_count
            damage_event_i=hazard.orig_yearset(year_i).event_index(event_i)+ens_i;
            YDS.damage(next_damage_year)=YDS.damage(next_damage_year)+EDS.damage(damage_event_i);
            if EDS.orig_event_flag(damage_event_i)
                YDS.orig_year_flag(next_damage_year)=1;
            else
                YDS.orig_year_flag(next_damage_year)=0;
            end
            if ens_i==0 && EDS.orig_event_flag(damage_event_i)==0
                orig_event_mismatch_count=orig_event_mismatch_count+1;
            elseif ens_i>0 && EDS.orig_event_flag(damage_event_i)==1
                prob_event_mismatch_count=prob_event_mismatch_count+1;
            end
        end % event_i
        next_damage_year=next_damage_year+1;
    end % ens_i
    
    % the progress management
    if mod(year_i,mod_step)==0
        mod_step          = 100;
        t_elapsed_year   = etime(clock,t0)/year_i;
        events_remaining  = n_years-year_i;
        t_projected_sec   = t_elapsed_year*events_remaining;
        if t_projected_sec<60
            msgstr = sprintf('est. %3.0f sec left (%i/%i events)',t_projected_sec,   year_i,n_years);
        else
            msgstr = sprintf('est. %3.1f min left (%i/%i events)',t_projected_sec/60,year_i,n_years);
        end
        if climada_global.waitbar
            waitbar(year_i/n_years,h,msgstr); % update waitbar
        else
            fprintf(format_str,msgstr); % write progress to stdout
            format_str=[repmat('\b',1,length(msgstr)) '%s']; % back to begin of line
        end
    end
    
end % year_i
if climada_global.waitbar
    close(h) % dispose waitbar
else
    fprintf(format_str,''); % move carriage to begin of line
end
t_elapsed = etime(clock,t0);
msgstr    = sprintf('processing yearset (%i original years, %i prob years each) took %3.2f sec',n_years,ens_size,t_elapsed);
fprintf('%s\n',msgstr);

if orig_event_mismatch_count>0
    fprintf('Warning: there seem to be %i orig_event mismatches (YDS.orig_year_flag likely useless)\n',orig_event_mismatch_count);
end
if prob_event_mismatch_count>0
    fprintf('Warning: there seem to be %i prob_event mismatches (YDS.orig_year_flag possibly useless)\n',prob_event_mismatch_count);
end

YDS.frequency=YDS.damage*0+1/length(YDS.damage); % each year occurrs once...

% final check whether we picked up all damage
YDS_ED=sum(YDS.damage)/n_years/(ens_size+1);
if abs(YDS_ED-EDS.ED)/EDS.ED>0.0001 % not zero, as we deal with large numbers
    fprintf('Warning: expected damage mismatch (EDS: %f, YDS: %f)\n',EDS.ED,YDS_ED);
end

return
