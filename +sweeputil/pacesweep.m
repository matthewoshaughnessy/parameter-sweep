% TODO - empty results if not divisible by number of cores?
% TODO - concatenating large results structures is very slow
% TODO - verify walltime is a string (time w/out quotes becomes [])
% TODO - only works (see retrieve script) when submitting with dirname '.'?
% TODO - bug in cluster mode if more procs than tasks?
% TODO - bug when trying to update code already on pace in ~/data/dirname/?
function out = pacesweep(dirname, jobname, queue, walltime, nodes, ppn)
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
%     retrieve_<jobname>.m script. When completed, the results will be
%     placed in <dirname>/results.mat.


% --- internal parameters ---
defaultqueue = 'davenporter';
defaultwalltime = '8:00:00';
matlabversion = 'r2016b';
username = 'moshaughnessy6';
headnode = 'davenporter';
email = 'moshaughnessy6@gatech.edu';


% --- parse inputs and initialize ---
if isempty(queue), queue = defaultqueue; end
if isempty(walltime), walltime = defaultwalltime; end
if isempty(nodes), nodes = 1; end
if isempty(ppn), ppn = 16; end
pacedirname = jobname;
if exist('tocopy','dir'); error('tocopy directory already exists'); end
mkdir(fullfile(dirname,'tocopy'));
copyfile(which('sweep'),[fullfile(dirname,'tocopy',filesep),'sweep.m']);
files = dir(dirname);  files = {files.name};  files(1:2) = []; % TODO
files(strcmp(files,'tocopy')) = [];
for i = 1:length(files)
  copyfile(fullfile(pwd,dirname,files{i}), ...
    [fullfile(pwd,dirname,'tocopy',filesep) files{i}]);
end
if ~exist(fullfile(dirname,'tocopy',[jobname '.m']),'file')
  rmdir(fullfile(dirname,'tocopy'),'s');
  error('MATLAB function %s.m does not exist');
end
njobs = nodes*ppn;


% --- create .m files ---
% file for each individual job
templatefile = fullfile(dirname,[jobname '.m']);
fh = fopen(fullfile(dirname,'tocopy','jobs.txt'),'w');
for i = 1:njobs
  destfile = fullfile(dirname,'tocopy',sprintf('%s_%d.m',jobname,i));
  matlabCommand = sprintf('run(''~/data/MATLAB/startup.m''); %s_%d();', ...
    jobname, i);
  system(sprintf('sed -e s/JOBNUM/%d/g -e s/TOTALJOBS/%d/g <%s>%s', ...
    i, njobs, templatefile, destfile));
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
  fullfile(dirname,'tocopy',['submit-' jobname '.txt'])));


% --- move files to pace ---
system(sprintf('scp -r %s moshaughnessy6@iw-dm-4.pace.gatech.edu:~/data/%s', ...
  fullfile(dirname,'tocopy'), pacedirname));


% --- submit jobs to pace ---
[~,out] = system([sprintf(...
  'ssh %s@%s.pace.gatech.edu bash -c "''cd ~/data/%s/; qsub submit-%s.txt''"', ...
  username, headnode, pacedirname, jobname) ''],'-echo');
%jobid = strtok(out,'.');


% --- write record file ---
fh = fopen(fullfile(dirname,'submission-record.txt'),'w');
fprintf(fh, 'Submitted %s -- %s', datestr(now), out);
fclose(fh);


% --- remove temporary files ---
rmdir(fullfile(dirname,'tocopy'),'s');


% --- create the retrieve script ---
system(sprintf(['sed ' ...
  '-e s/TEMPLATE_DIRNAME/%s/ ' ...
  '-e s/TEMPLATE_USERNAME/%s/ ' ...
  '-e s/TEMPLATE_JOBNAME/%s/ ' ...
  '-e s/TEMPLATE_HEADNODE/%s/ ' ...
  '< %s > %s'], ...
  dirname, username, jobname, headnode, ...
  fullfile(fileparts(which('sweeputil.pacesweep')),'retrieve_template.m'), ...
  fullfile(dirname,['retrieve_' jobname '.m'])));


end