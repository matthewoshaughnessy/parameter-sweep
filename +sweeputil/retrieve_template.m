% --- retrieve files ---
mkdir(fullfile('TEMPLATE_DIRNAME','results'));
system(['scp -r TEMPLATE_USERNAME@TEMPLATE_HEADNODE.pace.gatech.edu:~/data/' ...
  'TEMPLATE_JOBNAME/results* TEMPLATE_DIRNAME/results/'], '-echo');


% --- concatenate results ---
resultfiles = dir('./results/results*.mat');
if isempty(resultfiles), error('No results returned!'); end
resultfiles = {resultfiles.name};
[~, reindex] = sort(str2double(regexp(resultfiles,'\d+','match','once')));
resultfiles = resultfiles(reindex);
fprintf('\nConcatenating results: 1/%d...\n', length(resultfiles));
load(['TEMPLATE_DIRNAME/results/' resultfiles{1}]);
results = results1;
for i = 2:length(resultfiles)
  fprintf('Concatenating results: %d/%d.', i, length(resultfiles));
  load(['TEMPLATE_DIRNAME/results/' resultfiles{i}]); fprintf('.');
  assert(isequal(size(results),size(results1)));
  eval(sprintf('ind = ~cellfun(@isempty,results%d);',i)); fprintf('.');
  eval(sprintf('results(ind) = results%d(ind);',i)); fprintf('\n');
end
fprintf('Saving concatenated results...');
save(fullfile('TEMPLATE_DIRNAME','results.mat'),'results','-v7.3');
fprintf('done!\n');


% --- clean up ---
fprintf('Cleaning up...');
system(sprintf('rm -r %s', fullfile('TEMPLATE_DIRNAME','results')));
clear;
fprintf('done!\n');