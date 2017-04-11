% TODO document
% TODO support non-numerical data
% TODO support nonhomogenous data type
function A = getvar(results,varname)

  A = zeros(size(results));
  for i = 1:numel(A)
    A(i) = results{i}.(varname);
  end

end

