function s = short_ansp(n)
% SHORT_ANSP  Strip a parenthesised qualifier: "NATS (Continental)" -> "NATS".
    s = regexprep(char(n), '\s*\(.*\)$', '');
end
