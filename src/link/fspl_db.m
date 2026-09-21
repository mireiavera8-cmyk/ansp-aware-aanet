function L = fspl_db(d_km, f_mhz)
% FSPL_DB  Free-space path loss, d in km, f in MHz.
    L = 32.44 + 20*log10(d_km) + 20*log10(f_mhz);
end
