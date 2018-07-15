% TODO - empty results if not divisible by number of cores?
% TODO - concatenating large results structures is very slow
% TODO - verify walltime is a string (time without quotes becomes [])
% TODO - only works (see retrieve script) when submitting with dirname '.'?
% TODO - bug in cluster mode if more procs than tasks?
function out = pacesweep(jobname, filepath, varargin)
% INSTRUCTIONS:
%  1. Create the file <jobname>.m that contains the sweep command to run.
%     Use cluster mode with the templates JOBNUM and TOTALJOBS. The script
%     should save the results from sweep(...) in variable resultsJOBNUM,
%     saved in the .mat file resultsJOBNUM.
%  2. Put <jobname>.m, along with any dependencies (sweep.m will be added
%     automatically), in <dirname>
%  3. Call pacesweep. This function will:
%      - copy <jobname>.m and all dependencies to pace:~/data/<jobname>/
%      - create jobs.txt on pace:~/data/<jobname>/
%      - create a submission script,
%         pace:~/data/<jobname>/submit-<jobname>.txt
%      - submit the job on pace
%      - generate a matlab file in <dirname> to retrieve and concatenate
%        when the job has completed
%  4. When the job is completed (per email notification), run the
%     <jobname>_retrieve.m script. When completed, the results will be
%     placed in <dirname>/<jobname>_results.mat.
%
%  Updated 2018/05/22: overwrite files modified on server during transfer
%  Updated 2018/05/23: automatically remove old results, retrieval script, 
%                      and submission record if resubmitting
%  Updated 2018/06/29: include job name in title of submission record file
%  Updated 2018/07/02: changed name of retrieve and submission record files
% *Updated 2018/07/15: major revision


% -- parse inputs --
p = inputParser;
addRequired(p,  'jobname');
addRequired(p,  'filepath');
addParameter(p, 'excludedirs',   [], @(x) isstr(x) || iscell(x));
addParameter(p, 'queue',         'davenporter', @ischar);
addParameter(p, 'walltime',      '8:00:00', @ischar);
addParameter(p, 'matlabversion', 'r2016b', @(x) regexp(x,'r20[01]\d[ab]'));
addParameter(p, 'username',      'moshaughnessy6', @ischar);
addParameter(p, 'headnode',      'davenporter', @ischar);
addParameter(p, 'email',         'moshaughnessy6@gatech.edu', @ischar);
addParameter(p, 'nodes',         1, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'ppn',           24, @(x) isnumeric(x) && isscalar(x));
parse(p, jobname, filepath, varargin{:});
params = fieldnames(p.Results);
for i = 1:length(params)
  eval(sprintf('%1$s = p.Results.%1$s;', params{i}));
end


% --- initialize ---
[jobdir, filename, jobext] = fileparts(filepath);
njobs = nodes*ppn;
% remove old files
if exist('tocopy','dir')
  warning('Directory tocopy/ already exists. Overwrite?');
  pause();
  system('rm -r tocopy');
end
if exist(fullfile(jobdir,'retrieve.m'),'file') ...
    || exist(fullfile(jobdir,'submission-record.txt'),'file') ...
    || exist(fullfile(jobdir,'results.mat'),'file')
  fprintf('Found files from previous PACE job!\n');
  fprintf('Press return to overwrite, or CTRL-C to exit...');
  pause();
  fprintf('\n');
  if exist(fullfile(jobdir,'retrieve.m'),'file')
    delete(fullfile(jobdir,'retrieve.m'));
  end
  if exist(fullfile(jobdir,'submission-record.txt'),'file')
    delete(fullfile(jobdir,'submission-record.txt'));
  end
  if exist(fullfile(jobdir,'results.mat'),'file')
    delete(fullfile(jobdir, 'results.mat'));
  end
end
% create directory of files to copy to pace
mkdir('tocopy');
copyfile(which('sweep'),fullfile('tocopy','sweep.m'));
files = dir();
files = unique([{files.name} jobdir]);
excludedirs = [excludedirs {'tocopy','.','..','.DS_Store'}];
files = setdiff(files,excludedirs);
for i = 1:length(files)
  dirs = strsplit(files{i},filesep);
  dirs = dirs(~cellfun(@isempty,dirs));
  for k = 1:length(dirs)-1
    mkdir(fullfile('tocopy',dirs{1:k}));
  end
  copyfile(fullfile(files{i}), fullfile('tocopy',files{i}));
end
if ~exist(fullfile(jobdir,filename),'file')
  rmdir(fullfile(dirname,'tocopy'),'s');
  error('MATLAB function %s.m does not exist',filename);
else
  copyfile(fullfile(jobdir,[filename jobext]), ...
    fullfile('tocopy',jobdir,filename));
end


% --- create .m file for each core ---
fh = fopen(fullfile('tocopy','jobs.txt'),'w');
for i = 1:njobs
  destfile = fullfile('tocopy',sprintf('%s_%d.m',jobname,i));
  matlabCommand = sprintf('run(''~/data/MATLAB/startup.m''); %s_%d();', ...
    jobname, i);
  system(sprintf(['sed ' ...
    '-e s/JOBNAME/%s/g ' ...
    '-e s/JOBNUM/%d/g ' ...
    '-e s/TOTALJOBS/%d/g ' ...
    '< %s > %s'], ...
    jobname, i, njobs, filepath, destfile));
  fprintf(fh, 'matlab -nodisplay -singleCompThread -r "%s"\n', ...
    matlabCommand);
end
fclose(fh);


% --- create job submission file ---
system(sprintf(['sed ' ...
  '-e s/TEMPLATE_JOBNAME/%s/ ' ...
  '-e s/TEMPLATE_QUEUENAME/%s/ ' ...
  '-e s/TEMPLATE_WALLTIME/%s/ ' ...
  '-e s/TEMPLATE_NODES/%d/ ' ...
  '-e s/TEMPLATE_PPN/%d/ ' ...
  '-e s/TEMPLATE_EMAIL/%s/ ' ...
  '-e s/TEMPLATE_MATLABVERSION/%s/ ' ...
  '< %s > %s'], ...
  jobname, queue, walltime, nodes, ppn, email, matlabversion, ...
  fullfile(fileparts(which('sweeputil.pacesweep')),'submission-template.txt'), ...
  fullfile('tocopy',['submit-' jobname '.txt'])));


% --- move files to pace ---
system(sprintf('scp -pr ''%s'' ''moshaughnessy6@iw-dm-4.pace.gatech.edu:~/data/%s/''', ...
  fullfile('tocopy','.'), jobname));


% --- submit jobs to pace ---
[~,out] = system([sprintf(...
  'ssh %s@%s.pace.gatech.edu bash -c "''cd ~/data/%s/; qsub submit-%s.txt''"', ...
  username, headnode, jobname, jobname) ''],'-echo');
%jobid = strtok(out,'.');


% --- write record file ---
fh = fopen(fullfile(jobdir,'record.txt'),'w');
fprintf(fh, 'Submitted %s -- %s', datestr(now), out);
fclose(fh);


% --- remove temporary files ---
rmdir('tocopy','s');


% --- create the retrieve script ---
system(sprintf(['sed ' ...
  '-e s~TEMPLATE_DIRNAME~%s~ ' ...
  '-e s~TEMPLATE_USERNAME~%s~ ' ...
  '-e s~TEMPLATE_JOBNAME~%s~ ' ...
  '-e s~TEMPLATE_HEADNODE~%s~ ' ...
  '< %s > %s'], ...
  jobdir, username, jobname, headnode, ...
  fullfile(fileparts(which('sweeputil.pacesweep')),'retrieve_template.m'), ...
  fullfile(jobdir,'retrieve.m')));


end
