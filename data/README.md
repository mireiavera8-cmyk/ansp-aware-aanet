# Data

| File | Source | In git |
|---|---|---|
| `ansp_upper_490_1.json`, `ansp_lower_490_1.json` | EUROCONTROL ANSP airspace polygons, AIRAC 490, upper and lower layers | yes |
| `terrain_elevation.csv` | Copernicus DEM GLO-90 via the Open-Meteo elevation API, sampled at every M3 candidate site (`lat, lon, elevation_m, ruggedness_std_m, ruggedness_range_m`) | yes |
| `terrain_elevation_hex.csv` | Same, sampled at the hex-lattice and DME/VOR candidate sites (`fetch_hex_terrain.m`) | yes |
| `opensky_data_extended.csv` | OpenSky Network state vectors, 2023-05-15 08:00 to 09:00 UTC, box 43.67 to 56.33 N, -6.18 to 23.18 E | no (549 MB) |
| `opensky_data_validation.csv` | Same query, 2023-05-18 17:00 to 18:00 UTC (out-of-sample hour) | no (971 MB) |

## Reproducing the OpenSky pulls

The two CSVs are raw `state_vectors_data4` exports from the [OpenSky Network](https://opensky-network.org/) historical database (Trino/Impala access, research account). Columns used by the pipeline: `time, icao24, lat, lon, baroaltitude, onground`.

```sql
SELECT time, icao24, lat, lon, baroaltitude, velocity, heading, onground
FROM state_vectors_data4
WHERE time >= 1684137600 AND time < 1684141200            -- design hour; validation: 1684429200 .. 1684432800
  AND lat BETWEEN 43.67 AND 56.33 AND lon BETWEEN -6.18 AND 23.18
  AND hour >= 1684137600 AND hour < 1684141200
```

The query box is the analysis box (47 to 53 N, -1 to 18 E) grown by 370 km on every side, the radio-horizon reach of a station sitting on the box edge. Module 1 filters back to the analysis box; the ring exists only so the pull is a superset of anything a legally sited station could see.

Without the CSVs, everything downstream of M1 still runs from the committed checkpoints in `results/` (`tagged_data.mat` is the M1 output), so `make_figures`, the M3 to M9 modules and the web visualizer all work out of the box.
