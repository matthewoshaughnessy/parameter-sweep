function results = sweep(call, params, varargin)
% SWEEP  Run function or script, sweeping over multiple variables.
%   results = SWEEP(call,params) executes CALL, sweeping over every
%     combination of parameters specified in PARAMS.  CALL may be a
%     function handle, script to execute, or string of function call to
%     execute (potentially slow).  See below for CALL and PARAMS details.
%
%   CALL FORMATS:
%    1. Function handle mode
%       example : sweep(@functionName,params,...)
%       The parameters specified in the params input will be used, in
%       order, as the inputs to the function.
%    2. Function mode
%       example : sweep('[out1 out2] = functionName(in1,in2)',params,...)
%       The inputs will be matched with the corresponding fields in params,
%       and the output variable names in the results structure will be
%       matched with the names you input.  This mode allows you to specify
%       other inputs not in the params struct as long as they are literal
%       values, not variables that won't exist in the scope of sweep.
%    3. Script mode
%       example: sweep('scriptName',params,...)
%       The values in the params struct will be assigned before the script
%       is executed.
%
%   PARAMS FORMATS:
%    For each parameter, the values to sweep should be specified in a cell
%    array.  Exception: if the parameter takes only scalar values, an array
%    may be used.
%    example: params.val1 = {1, 2, 3} will sweep three values
%             params.val1 = [1, 2, 3] will sweep three values
%             params.val1 = {[1 2], [3 4], [5 6]} will sweep three values
%
%   ADDITIONAL PARAMETERS - optional name/value pairs:
%    - nTrials     : number of trials to perform for each parameter
%                    configuration (results from every trial will be
%                    returned)
%    - varsToStore : in script mode, use to specify a cell array of
%                    variable names to store for each trial
%    - nOutputs    : number of outputs to request (in function handle mode)
%    - time        : adds a 'time' field to the results field indicating
%                    the execution time (sec) of each trial (default: true)
%    - jobNum      : for running large jobs on a cluster, specifies the
%                    index of this job.  See 'cluster mode', below
%    - totalJobs   : for running large jobs on a cluster, specifies the
%                    total number of jobs.  See 'cluster mode', below
%
%   OUTPUT:
%    The output of SWEEP is a cell array containing one cell per
%    combination of parameters.  Each cell contains a 1xnTrials structure
%    array with the following fields:
%     - (function input) allOutputs   : cell array containing outputs from
%       this run
%     - (script input) variable names : values of variables at completion
%       of script execution (optionally specified by varsToStore)
%     - (if time not disabled) time   : execution time (seconds)
%
%   CLUSTER MODE:
%    To facilitate large parameter sweeps on clusters, the optional
%    parameters 'jobNum' and 'totalJobs' may be specified.
%    example: split a parameter sweep between three nodes
%      node1>> results1 = sweep(..., 'jobNum', 1, 'totalJobs', 3)
%      node2>> results2 = sweep(..., 'jobNum', 2, 'totalJobs', 3)
%      node3>> results3 = sweep(..., 'jobNum', 3, 'totalJobs', 3)
%
%   Matt O'Shaughnessy, v0.1 - 3 January 2016
%   Please send suggestions and bugs to matthewoshaughnessy@gatech.edu
%

% --- get and validate input ---
valFuncs.params = @(x) isstruct(x) && isscalar(x);
valFuncs.posInt = @(x) isscalar(x) && round(x)==x;
valFuncs.varsToStore = @(x) iscell(x) && all(cellfun(ischar,x));
valFuncs.time = @islogical;
p = inputParser;
p.addRequired('call');
p.addRequired('params', valFuncs.params);
p.addParameter('nTrials', 1, valFuncs.posInt);
p.addParameter('varsToStore', {}, valFuncs.varsToStore);
p.addParameter('nOutputs', [], valFuncs.posInt);
p.addParameter('time', true, valFuncs.time);
p.addParameter('jobNum', [], valFuncs.posInt);
p.addParameter('totalJobs', [], valFuncs.posInt);
p.parse(call,params,varargin{:});
opt = p.Results;

% --- validate input ---
paramNames = fieldnames(params);
nParams = length(paramNames);
clusterMode = ~isempty(opt.jobNum) && ~isempty(opt.totalJobs);
% specified call isn't function handle or string
if ~(isa(call,'function_handle') || isa(call,'char'))
    error('Call must be fx handle or string function/script call');
end
% specified params contain invalid variable names
if any(~cellfun(@isvarname,paramNames))
    error('Parameter(s) %s are invalid (not a valid var name).', ...
        strjoin(paramNames(~cellfun(@isvarname,paramNames))));
end
% specified params contain reserved words
if any(cellfun(@iskeyword,paramNames))
    error('Parameter(s) %s are invalid (reserved word).', ...
        strjoin(paramNames(cellfun(@iskeyword,paramNames))));
end
% only one of jobNum and totalJobs specified
if xor(~isempty(opt.jobNum), ~isempty(opt.jobNum))
    error('In cluster mode, both jobNum and totalJobs must be input.');
end
% invalid jobNum
if clusterMode && opt.jobNum > opt.totalJobs
    error('Specified job number greater than total number of jobs.');
end

% --- prepare parameters to sweep ---
% (make a N-dim cell array.  Each cell has a 1xN cell containing one
%  combination of parameters)
% determine array/cell
subsOpen = repmat('(',1,nParams);
subsClosed = repmat(')',1,nParams);
subsOpen(structfun(@iscell,params)) = '{';
subsClosed(structfun(@iscell,params)) = '}';
% create cell array
str = 'combinations = cell(';
for i = 1:nParams
    nValues = length(params.(paramNames{i}));
    str = [str num2str(nValues)];
    str = [str ','];
end
str = [str(1:end-1) ');'];
% nested for loop - one level per parameter to sweep
for i = 1:nParams
    str = [str sprintf('for p%d = 1:%d, ', ...
        i, length(params.(paramNames{i})))];
end
str = [str sprintf('for i = 1:%d, ', nParams)];
% assign combination of parameters for cell array
str = [str 'combinations{'];
for i = 1:nParams
    str = [str sprintf('p%d,',i)];
end
str = [str(1:end-1) '} = {'];
for i = 1:nParams
    str = [str sprintf('params.(paramNames{%d})%cp%i%c,', ...
        i, subsOpen(i), i, subsClosed(i))];
end
str = [str(1:end-1) '}; '];
% end nested for loops
for i = 1:nParams
    str = [str 'end,'];
end
str = [str 'end'];
% create the cell array of parameter combinations
eval(str);
nCombinations = numel(combinations); %#ok

% --- if cluster mode, pick the combinations for this node ---
if clusterMode
    jobsPerNode = nCombinations / opt.totalJobs;
    combInds = zeros(ceil(jobsPerNode), opt.totalJobs);
    wastedIncr = round(nCombinations/(numel(combInds)-nCombinations));
    wastedInds = wastedIncr:wastedIncr:numel(combInds);
    k = 1;
    for i = 1:numel(combInds)
        if any(i==wastedInds)
            combInds(i) = NaN;
        else
            combInds(i) = k;
            k = k + 1;
        end
    end
    combinationIndsThisNode = combInds(:,opt.jobNum);
    combinationIndsThisNode(isnan(combinationIndsThisNode)) = [];
    combinationIndsThisNode = reshape(combinationIndsThisNode,1,[]);
else
    combinationIndsThisNode = 1:nCombinations;
end

% --- parse function/script call ---
results = cell(size(combinations));
if isa(call,'function_handle')
    % function handle mode
    mode = 'function_handle';
    func = call;
elseif ~isempty(strfind(call,'('))
    % function mode - need to parse inputs and outputs
    mode = 'function';
    [lhsStr, rhsStr] = strtok(call,'=');
    outputs = strsplit(lhsStr,{' ',','});
    for i = 1:length(outputs), outputs{i}(...
            outputs{i}=='['|outputs{i}==']'|...
            outputs{i}==' '|outputs{i}==',') = [];
    end
    outputs(cellfun(@isempty,outputs)) = [];
    rhsStr = rhsStr(2:end);
    func = str2func(strtrim(rhsStr(2:find(rhsStr=='(',1,'first')-1)));
    inputNames.begin = find(rhsStr=='(',1,'first')+1;
    inputNames.end = find(rhsStr==')',1,'last')-1;
    inputNames = strsplit(strtrim(rhsStr(inputNames.begin:inputNames.end)),',');
    for i = 1:length(inputNames), inputNames{i}(...
            inputNames{i}==','|inputNames{i}=='('|inputNames{i}==')') = [];
    end
    inputNames(cellfun(@isempty,inputNames)) = [];
else
    mode = 'script';
    swVars.call = str2func(call);
    swVars.combinations = combinations;
    swVars.opt = opt;
    swVars.params = params;
    swVars.paramNames = paramNames;
    swVars.nParams = nParams;
    swVars.results = results;
    swVars.nCombinations = combinations;
    swVars.excludedVars = {'swVars_i','swVars_k','swVars_m'};
    clearvars -except swVars mode
end

% --- function handle mode ---
if strcmp(mode,'function_handle')
    if isempty(opt.nOutputs), opt.nOutputs = nargout(func); end
    out = cell(1,opt.nOutputs);
    for i = combinationIndsThisNode
        for k = 1:opt.nTrials
            fprintf('Combination %d of %d, trial %d of %d...', ...
                i, nCombinations, k, opt.nTrials);
            if opt.time, tic; end
            [out{:}] = func(combinations{i}{:});
            results{i}(k).time = toc;
            results{i}(k) = out;
            results{i}(k).inputs = combinations{i};
            if opt.time, fprintf('%f sec\n', results{i}(k).time),
            else fprintf('done.\n'); end
        end
    end
end

% --- function mode ---
if strcmp(mode,'function')
    if ~isempty(opt.nOutputs), warning(['Specified nOutputs=%d, ' ...
            'call has %d outputs.  Using %d.'], ...
            opt.nOutputs,length(outputs),length(outputs));
    end
    out = cell(1,length(outputs));
    for i = combinationIndsThisNode
        % replace parameters in inputs with these
        funcInputs = cell(1,length(inputNames));
        for k = 1:length(inputNames)
            isSwept = inputNames{k}(end)=='*' || inputNames{k}(1)=='*';
            if isSwept
                paramName = inputNames{k}(inputNames{k}~='*');
                paramNum = find(strcmp(paramName,paramNames));
                if isempty(paramNum)
                    error('Param to sweep %s not input.', paramName);
                end
                funcInputs{k} = combinations{i}{paramNum};
            else
                funcInputs{k} = inputNames{k};
            end
        end
        % execute
        for k = 1:opt.nTrials
            fprintf('Combination %d of %d, trial %d of %d...', ...
                i, nCombinations, k, opt.nTrials);
            if opt.time, tic; end
            [out{:}] = func(combinations{i}{:});
            results{i}(k).allOutputs = out;
            results{i}(k).time = toc;
            results{i}(k).inputs = combinations{i};
            if opt.time && opt.nTrials==1
                fprintf('%f sec\n', results{i}.time),
            elseif opt.time
                fprintf('%f sec\n', results{i}{k}.time);
            else
                fprintf('done.\n');
            end
        end
    end
end

% --- script mode ---
if strcmp(mode,'script')
    clearvars mode
    for swVars_i = 1:swVars.nCombinations
        for swVars_k = 1:swVars.opt.nTrials
            % set inputs for this parameter combination
            fprintf('Combination %d of %d, trial %d of %d...', ...
                swVars_i, numel(swVars.combinations), ...
                swVars_k, swVars.opt.nTrials);
            for swVars_m = 1:swVars.nParams
                eval(sprintf('%s = swVars.combinations{%d}{%d};', ...
                    swVars.paramNames{swVars_m}, swVars_i, swVars_m));
            end
            % execute
            if swVars.opt.time, tic; end
            swVars.call();
            swVars.results{swVars_i}(swVars_k).inputs = ...
                swVars.combinations{swVars_i};
            if swVars.opt.time
                swVars.results{swVars_i}(swVars_k).time = toc;
            end
            % store results
            swVars.vars = whos;
            swVars.vars = {swVars.vars.name};
            for swVars_m = 1:length(swVars.vars)
                swVars.varName = swVars.vars{swVars_m};
                swVars.store = (isempty(swVars.opt.varsToStore) || ...
                    any(strcmp(swVars.varName, swVars.opt.varsToStore))) && ...
                    ~any(strcmp(swVars.varName, swVars.excludedVars));
                if swVars.store
                    eval(sprintf('swVars.results{%d}(%d).%s = %s;', ...
                        swVars_i, swVars_k, ...
                        swVars.varName, swVars.varName));
                end
            end
            if swVars.opt.time
                fprintf('%f sec\n', swVars.results{swVars_i}(swVars_k).time);
            else
                fprintf('done.\n');
            end
        end
    end
    results = swVars.results;
end

end