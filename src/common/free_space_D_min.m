function D_min_km = free_space_D_min(R_km, ci_required_db)
% FREE_SPACE_D_MIN  Minimum co-channel separation for two equal-power cells
%   of radius R_km under free-space C/I: C/I[dB] ~ 20*log10((D-R)/R).
    D_min_km = R_km * (1 + 10^(ci_required_db/20));
end
