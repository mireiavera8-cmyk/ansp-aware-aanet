function v = getfielddef(s, name, default)
% GETFIELDDEF  s.(name) if the field exists, otherwise default.
    if isfield(s, name), v = s.(name); else, v = default; end
end
