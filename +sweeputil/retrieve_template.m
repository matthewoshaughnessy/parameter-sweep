% --- retrieve files ---
mkdir(fullfile('TEMPLATE_DIRNAME','results'));
system(['scp -r TEMPLATE_USERNAME@TEMPLATE_HEADNODE.pace.gatech.edu:~/data/' ...
  'TEMPLATE_JOBNAME/results* TEMPLATE_DIRNAME/results/'], '-echo');


% --- concatenate results ---
resultfiles = dir('./results/results*.mat');
if isempty(resultfiles), error('No results returned!'); end
resultfiles = {resultfiles.name};
fprintf('\nConcatenating results: 1/%d...\n', length(resultfiles));
load(['TEMPLATE_DIRNAME/results/' resultfiles{1}]);
results = results1;
for i = 2:length(resultfiles)
  fprintf('Concatenating results: %d/%d...\n', i, length(resultfiles));
  load(['TEMPLATE_DIRNAME/results/' resultfiles{i}]);
  assert(isequal(size(results),size(results1)));
  for k = 1:numel(results)
    if eval(sprintf('~isempty(results%d{k})',i))
      eval(sprintf('results{k} = results%d{k};',i));
    end
  end
end
save(fullfile('TEMPLATE_DIRNAME','results.mat'),'results');
fprintf('Done!\n\n');


% --- clean up ---
system(sprintf('rm -r %s', fullfile('TEMPLATE_DIRNAME','results')));
clear;