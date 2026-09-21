/* app.js — ANSP border-crossing exposure visualizer (Leaflet).
 * Reads window.VIZ_DATA and window.ANSP_GEOJSON from data/viz_data.js, written by
 * prepare_web_data.m from the M1/M2/M2b results. Draws the core and extended boxes,
 * ANSP polygons, aircraft tracks split into one polyline per same-ANSP run (raw tag
 * changes), M2's hysteresis-confirmed crossing markers, the four headline N=12
 * ground-station topologies, and the terrain / water / DME / hotspot environment layers.
 * Clicking an ANSP legend row isolates that ANSP; clicking again resets. */

const D = window.VIZ_DATA;
const GEOJSON = window.ANSP_GEOJSON;

const ANSP_BY_IDX = {};   // 1-based ANSP index -> {name, color, points}
D.ansp.forEach((a, i) => { ANSP_BY_IDX[i + 1] = a; });
const ANSP_BY_NAME = {};  // name -> color, for the GeoJSON style function
D.ansp.forEach((a) => { ANSP_BY_NAME[a.name] = a.color; });

const FALLBACK_COLOR = '#898781';

// ── MAP ──────────────────────────────────────────────────────────────────
const map = L.map('map', { renderer: L.canvas(), preferCanvas: true });

// OSM standard tiles: key-free.
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors',
    subdomains: 'abc',
    maxZoom: 19,
}).addTo(map);

const boxBounds = (b) => [[b.lat_min, b.lon_min], [b.lat_max, b.lon_max]];

const layers = {};

// Core box: station placement zone and analysis scope. Extended box: OpenSky query
// extent, one maximum coverage radius wider on every side (acquisition only).
layers.corridor = L.rectangle(boxBounds(D.corridor_box), {
    color: '#52514e', weight: 2, fill: false,
}).bindTooltip('Core box — ground-station placement zone, and what M1 filters the analysis data to',
    { sticky: true });

layers.dataBox = L.layerGroup();
if (D.data_box) {
    L.rectangle(boxBounds(D.data_box), {
        color: '#b8860b', weight: 2, dashArray: '8 6', fill: false,
    }).bindTooltip(
        '<div class="geom-tooltip"><b>Extended box</b><br>The OpenSky query extent the raw ' +
        'aircraft data was pulled over. Acquisition only — the analysis scope is the core box.</div>',
        { sticky: true }).addTo(layers.dataBox);
}

// Dataset geometry layers (corridor line, hypothetical worst-case edge stations, radio
// horizon), all from D.geometry / D.corridor_line / D.edge_gs; degrade to empty if absent.
const GEOM = D.geometry || null;
const EDGE_COLOR = '#8c1d18';       // worst-case edge station — dark brick
const HORIZON_COLOR = '#2f6f7d';    // radio horizon — steel teal, unused elsewhere

layers.corridorLine = L.layerGroup();
(D.corridor_line || []).forEach((w, i, arr) => {
    if (i < arr.length - 1) {
        L.polyline([[w.lat, w.lon], [arr[i + 1].lat, arr[i + 1].lon]], {
            color: '#6a2d8c', weight: 3, opacity: 0.8,
        }).bindTooltip('Corridor reference line — London – Frankfurt – Vienna', { sticky: true })
          .addTo(layers.corridorLine);
    }
    L.circleMarker([w.lat, w.lon], {
        radius: 5, color: '#6a2d8c', weight: 2, fillColor: '#fff', fillOpacity: 1,
    }).bindTooltip(
        `<div class="geom-tooltip"><b>${w.name}</b><br>` +
        `${w.margin_km.toFixed(0)} km to the nearest box edge</div>`,
        { sticky: true }
    ).addTo(layers.corridorLine);
});

layers.edgeGs = L.layerGroup();
layers.horizon = L.layerGroup();
if (GEOM) {
    (D.edge_gs || []).forEach((g) => {
        L.circle([g.lat, g.lon], {
            radius: GEOM.R_outer_km * 1000, color: EDGE_COLOR, weight: 1.2,
            dashArray: '6 5', fillColor: EDGE_COLOR, fillOpacity: 0.04, opacity: 0.6,
        }).addTo(layers.edgeGs);
        L.circle([g.lat, g.lon], {
            radius: GEOM.R_inner_km * 1000, color: EDGE_COLOR, weight: 1.4,
            fill: false, opacity: 0.8,
        }).addTo(layers.edgeGs);
        L.circleMarker([g.lat, g.lon], {
            radius: 6, color: EDGE_COLOR, weight: 2.5, fillColor: '#fff', fillOpacity: 1,
        }).bindTooltip(
            `<div class="geom-tooltip"><b>Worst case — ${g.name}</b><br>` +
            `Hypothetical station sited exactly on the core-box edge, the furthest out a ` +
            `station is allowed to go. Not placed by any module.<br>` +
            `Soft edge at F=${GEOM.fade_margin_db} dB: certain to ${GEOM.R_inner_km} km, ` +
            `zero beyond ${GEOM.R_outer_km} km (nominal cell radius ${GEOM.gs_radius_km} km).<br>` +
            `It therefore serves aircraft up to ${GEOM.R_outer_km} km outside the core box — ` +
            `which is why OpenSky was queried over a box ${GEOM.ext_margin_km} km wider on ` +
            `every side. The ring contains this station's whole reach, so the raw pull could ` +
            `never be the thing that limits it.</div>`,
            { sticky: true }
        ).addTo(layers.edgeGs);

        L.circle([g.lat, g.lon], {
            radius: GEOM.horizon_floor_km * 1000, color: HORIZON_COLOR, weight: 1.2,
            dashArray: '2 6', fill: false, opacity: 0.75,
        }).bindTooltip(
            `<div class="geom-tooltip"><b>Radio horizon — ${GEOM.horizon_floor_km} km</b><br>` +
            `${GEOM.gs_mast_height_m} m mast to an aircraft at the dataset's altitude floor ` +
            `(${GEOM.alt_min_m} m); ${GEOM.horizon_ceil_km} km at its ceiling ` +
            `(${GEOM.alt_max_m} m). 4/3-earth geometry, same expression as M7.<br>` +
            `Line of sight is not the binding limit here — the soft coverage edge ` +
            `(${GEOM.R_outer_km} km) is, and it sits well inside the ${GEOM.ext_margin_km} km ring.</div>`,
            { sticky: true }
        ).addTo(layers.horizon);
    });
}

// ── ANSP POLYGONS ─────────────────────────────────────────────────────────
layers.polys = L.geoJSON(GEOJSON, {
    style: (feature) => {
        const color = ANSP_BY_NAME[feature.properties.name] || FALLBACK_COLOR;
        return { color, weight: 1.5, fillColor: color, fillOpacity: 0.10, opacity: 0.6 };
    },
    onEachFeature: (feature, layer) => {
        layer.bindTooltip(feature.properties.name, { className: 'ansp-tooltip', sticky: true });
        layer.on('mouseover', () => layer.setStyle({ fillOpacity: 0.22, weight: 2.5 }));
        layer.on('mouseout', () => {
            if (!isolatedAnsp) layer.setStyle({ fillOpacity: 0.10, weight: 1.5 });
        });
    },
});

// ── AIRCRAFT TRACKS — one polyline per contiguous same-ANSP run ──────────
layers.tracks = L.layerGroup();
const trackSegments = [];   // {ansp_name, polyline}
const acSegments = {};      // ac id -> [polyline, ...] for click-highlight

D.tracks.forEach((t) => {
    const n = t.lat.length;
    const segs = acSegments[t.id] = [];
    let i = 0;
    while (i < n - 1) {
        let j = i;
        while (j < n - 1 && t.ansp[j + 1] === t.ansp[i]) j++;
        // segment covers points i..j (same ANSP); include point j+1 too so
        // consecutive segments visually touch (no gaps at the boundary)
        const end = Math.min(j + 1, n - 1);
        const pts = [];
        for (let k = i; k <= end; k++) pts.push([t.lat[k], t.lon[k]]);
        const ansp = ANSP_BY_IDX[t.ansp[i]];
        const color = ansp ? ansp.color : FALLBACK_COLOR;
        const pl = L.polyline(pts, { color, weight: 2, opacity: 0.55 });
        pl.bindTooltip(
            `<div class="ac-tooltip"><b>Aircraft #${t.id}</b><br>${ansp ? ansp.name : 'unknown'}` +
            `<br>${t.n_crossings} confirmed border crossing${t.n_crossings === 1 ? '' : 's'}</div>`,
            { sticky: true }
        );
        pl.addTo(layers.tracks);
        trackSegments.push({ anspName: ansp ? ansp.name : null, polyline: pl });
        segs.push(pl);
        i = j + 1;
    }
});

// ── CONFIRMED BORDER-CROSSING MARKERS (M2, hysteresis-filtered) ──────────
layers.crossings = L.layerGroup();
const fmtTime = (unixSec) => {
    const d = new Date(unixSec * 1000);
    return d.toISOString().substr(11, 8) + ' UTC';
};
(D.crossings || []).forEach((c) => {
    const from = ANSP_BY_IDX[c.from], to = ANSP_BY_IDX[c.to];
    L.circleMarker([c.lat, c.lon], {
        radius: 4, color: '#0b0b0b', weight: 1, fillColor: '#0b0b0b', fillOpacity: 0.75,
    }).bindTooltip(
        `<div class="xing-tooltip"><b>Aircraft #${c.ac_id}</b><br>` +
        `${from ? from.name : '?'} &rarr; ${to ? to.name : '?'}<br>${fmtTime(c.time)}</div>`,
        { sticky: true }
    ).addTo(layers.crossings);
});

// ── ADD DEFAULT-ON LAYERS, FIT VIEW ─────────────────────────────────────────
// Tracks default to OFF (see index.html) — useful for spotting congestion,
// but drawn only when asked for, so it doesn't compete with topology/
// environment layers on first load.
layers.corridor.addTo(map);
layers.dataBox.addTo(map);
layers.corridorLine.addTo(map);
layers.polys.addTo(map);
layers.crossings.addTo(map);
// Fit to the extended box, not the core box — otherwise the ring the data
// was gathered over sits off-screen on first load, which is the one thing
// this view exists to show.
map.fitBounds(boxBounds(D.data_box || D.corridor_box), { padding: [20, 20] });

// ── STATS + HEADLINE ───────────────────────────────────────────────────────
document.getElementById('s-aircraft').textContent = D.meta.n_aircraft.toLocaleString();
document.getElementById('s-vectors').textContent  = D.meta.n_vectors.toLocaleString();
document.getElementById('s-span').textContent     = D.meta.span_min.toFixed(1);
document.getElementById('s-ansp').textContent     = D.ansp.length;

document.getElementById('headline').innerHTML =
    `Of <b>${D.summary.n_aircraft}</b> aircraft in the corridor this hour, ` +
    `<b>${D.summary.pct_aircraft_crossing}%</b> (${D.summary.n_aircraft_crossing}) cross at least ` +
    `one ANSP border, with <b>${D.summary.total_crossings}</b> confirmed crossings total ` +
    `(hysteresis &ge;${D.summary.hysteresis_n} pings).`;

document.getElementById('note').textContent =
    `${D.meta.n_aircraft.toLocaleString()} trajectories, downsampled at ${D.meta.sample_sec}s ` +
    `(exact on every ANSP-tag change). Track color = raw ANSP tag; dark dots = confirmed crossings only. ` +
    `Tracks are off by default — toggle "Aircraft tracks" above to see corridor congestion.`;

// ── ANSP LEGEND (dynamic, click to isolate) ───────────────────────────────
let isolatedAnsp = null;

function setIsolation(name) {
    isolatedAnsp = (isolatedAnsp === name) ? null : name;

    layers.polys.eachLayer((layer) => {
        const match = layer.feature.properties.name === isolatedAnsp;
        const dim = isolatedAnsp && !match;
        layer.setStyle({ fillOpacity: dim ? 0.03 : (match ? 0.28 : 0.10), opacity: dim ? 0.15 : 0.6 });
    });
    trackSegments.forEach(({ anspName, polyline }) => {
        const match = anspName === isolatedAnsp;
        const dim = isolatedAnsp && !match;
        polyline.setStyle({ opacity: dim ? 0.06 : (match ? 0.9 : 0.55) });
        if (match) polyline.bringToFront();
    });

    document.querySelectorAll('.ansp-row').forEach((el) => {
        el.style.fontWeight = (el.dataset.name === isolatedAnsp) ? '700' : '400';
    });
}

// Only ANSPs with real traffic this hour get a legend row — the GeoJSON
// spans 43 named regions across both layers, most outside this corridor
// (0 points, sharing a neutral tone on the map, see prepare_web_data.m).
const legendEl = document.getElementById('ansp-legend');
const activeAnsp = D.ansp.filter((a) => a.points > 0);
const totalPts = activeAnsp.reduce((s, a) => s + a.points, 0);
activeAnsp.slice().sort((a, b) => b.points - a.points).forEach((a) => {
    const row = document.createElement('div');
    row.className = 'ansp-row';
    row.dataset.name = a.name;
    const pct = totalPts ? (100 * a.points / totalPts).toFixed(1) : '0.0';
    row.innerHTML =
        `<span class="swatch-fill" style="background:${a.color}"></span>` +
        `<span class="name">${a.name}</span><span class="pct">${pct}%</span>`;
    row.addEventListener('click', () => setIsolation(a.name));
    legendEl.appendChild(row);
});

// ── TOP PAIRS LIST ─────────────────────────────────────────────────────────
const pairsEl = document.getElementById('pairs-list');
if (!D.top_pairs || D.top_pairs.length === 0) {
    pairsEl.innerHTML = '<p class="note">No confirmed crossings.</p>';
} else {
    D.top_pairs.forEach((p) => {
        const a = ANSP_BY_IDX[p.a], b = ANSP_BY_IDX[p.b];
        const row = document.createElement('div');
        row.className = 'pair-row';
        row.innerHTML =
            `<span class="names">${a ? a.name : '?'} &harr; ${b ? b.name : '?'}</span>` +
            `<span class="count">${p.count}</span>`;
        pairsEl.appendChild(row);
    });
}

// ── LAYER TOGGLES ──────────────────────────────────────────────────────────
const bind = (id, layer) => {
    const el = document.getElementById(id);
    el.addEventListener('change', () => {
        if (el.checked) layer.addTo(map); else map.removeLayer(layer);
    });
};
bind('t-polys', layers.polys);
bind('t-corridor', layers.corridor);
bind('t-data-box', layers.dataBox);
bind('t-corridor-line', layers.corridorLine);
bind('t-edge-gs', layers.edgeGs);
bind('t-horizon', layers.horizon);
bind('t-tracks', layers.tracks);
bind('t-crossings', layers.crossings);

// Geometry hint: the two boxes in km and the argument connecting them, on screen
// rather than only in tooltips (tracks stop at the core box, the analysis boundary).
const geomHintEl = document.getElementById('geom-hint');
if (GEOM) {
    geomHintEl.innerHTML =
        `Core box <b>${GEOM.core_width_km} × ${GEOM.core_height_km} km</b> (stations may be ` +
        `sited here) inside an extended box <b>${GEOM.data_width_km} × ${GEOM.data_height_km} km</b> ` +
        `(OpenSky queried here), a <b>${GEOM.ext_margin_km} km</b> ring on every side. ` +
        `That ring is one maximum coverage radius: a station on the core edge reaches ` +
        `${GEOM.R_outer_km} km out (soft edge, F=${GEOM.fade_margin_db} dB) and sees to ` +
        `${GEOM.horizon_floor_km} km, so the raw pull covers everything it could serve. ` +
        `The extended box is acquisition only — the analysis scope is the core box, which is ` +
        `where the tracks stop.`;
} else {
    geomHintEl.textContent =
        'Geometry layers need a viz_data.js rebuilt with the current prepare_web_data.m.';
}

// Ground-station topologies: one layer group per headline strategy. Station fill = owning
// ANSP colour, accent ring + coverage circles = topology, so overlays stay legible. Naive on by default.
const TOPO_ACCENT = {
    naive:     '#1f4e8c',
    aware:     '#b5450d',
    hex:       '#6a2d8c',
    optimized: '#0f8a3d',
};
const TOPO_DEFAULT_ON = 'naive';

layers.topologies = {};   // key -> L.layerGroup
const topoToggleEl = document.getElementById('topo-toggles');

(D.topologies || []).forEach((topo) => {
    const accent = TOPO_ACCENT[topo.key] || '#555';
    const grp = L.layerGroup();

    topo.stations.forEach((st, i) => {
        const ansp = ANSP_BY_NAME[st.ansp_name];
        const fill = ansp || FALLBACK_COLOR;

        L.circle([st.lat, st.lon], {
            radius: topo.R_outer_km * 1000, color: accent, weight: 1.2,
            dashArray: '5 5', fill: false, opacity: 0.55,
        }).addTo(grp);
        L.circle([st.lat, st.lon], {
            radius: topo.R_inner_km * 1000, color: accent, weight: 1.2,
            fill: false, opacity: 0.75,
        }).addTo(grp);
        L.circleMarker([st.lat, st.lon], {
            radius: 7, color: accent, weight: 2.5,
            fillColor: fill, fillOpacity: 0.9,
        }).bindTooltip(
            `<div class="station-tooltip"><b>${topo.label}</b> — station ${i + 1}/${topo.n_stations}` +
            `<br>ANSP: ${st.ansp_name}</div>`,
            { sticky: true }
        ).addTo(grp);
    });

    layers.topologies[topo.key] = grp;
    if (topo.key === TOPO_DEFAULT_ON) grp.addTo(map);

    const row = document.createElement('label');
    row.className = 'topo-row';
    row.innerHTML =
        `<input type="checkbox" id="topo-${topo.key}" ${topo.key === TOPO_DEFAULT_ON ? 'checked' : ''}>` +
        `<span class="accent-ring" style="--accent:${accent}"></span>` +
        `<span class="topo-label">${topo.label}</span>` +
        `<span class="topo-stat">N=${topo.n_stations} · ${topo.pct_inter}% inter-ANSP</span>`;
    topoToggleEl.appendChild(row);
    row.querySelector('input').addEventListener('change', (e) => {
        if (e.target.checked) grp.addTo(map); else map.removeLayer(grp);
    });
});

// Environment and constraints: terrain (Copernicus DEM), water-excluded sites, DME/VOR
// beacons, M2b border hotspots. All default OFF and independent of any topology layer.

// Elevation -> color: green (low) -> amber -> brown (high), simple 2-stop
// lerp in hex space. 2000m covers this corridor's real range (coastal
// plains through the Alpine fringe) without clipping.
function hexLerp(a, b, t) {
    const pa = [1, 3, 5].map((i) => parseInt(a.substr(i, 2), 16));
    const pb = [1, 3, 5].map((i) => parseInt(b.substr(i, 2), 16));
    const c = pa.map((v, i) => Math.round(v + (pb[i] - v) * t));
    return `#${c.map((v) => v.toString(16).padStart(2, '0')).join('')}`;
}
function elevationColor(elev_m) {
    const t = Math.max(0, Math.min(1, elev_m / 2000));
    return t < 0.5 ? hexLerp('#3a9d4f', '#e8c547', t / 0.5) : hexLerp('#e8c547', '#8b4a2b', (t - 0.5) / 0.5);
}

layers.terrain = L.layerGroup();
layers.water = L.layerGroup();
(D.terrain || []).forEach((p) => {
    if (p.is_water) {
        L.circleMarker([p.lat, p.lon], {
            radius: 4, color: '#2a78d6', weight: 1, fillColor: '#2a78d6', fillOpacity: 0.5,
        }).bindTooltip(
            `<div class="terrain-tooltip"><b>Excluded — open water</b><br>Copernicus DEM elevation = 0m</div>`,
            { sticky: true }
        ).addTo(layers.water);
    } else {
        L.circleMarker([p.lat, p.lon], {
            radius: 3.5, color: elevationColor(p.elevation_m), weight: 0,
            fillColor: elevationColor(p.elevation_m), fillOpacity: 0.75,
        }).bindTooltip(
            `<div class="terrain-tooltip"><b>${p.elevation_m.toFixed(0)}m elevation</b>` +
            `<br>Ruggedness (std): ${p.ruggedness_std_m.toFixed(0)}m</div>`,
            { sticky: true }
        ).addTo(layers.terrain);
    }
});

// DME/VOR beacons: real markers + an illustrative (not a hard cutoff — the
// actual siting-cost model is a continuous 1/d term) 40km influence ring,
// purely to give the eye a sense of scale near each beacon.
const DME_ILLUSTRATIVE_RADIUS_KM = 40;
layers.dme = L.layerGroup();
(D.dme_beacons || []).forEach((b) => {
    L.circle([b.lat, b.lon], {
        radius: DME_ILLUSTRATIVE_RADIUS_KM * 1000, color: '#7a4fc4', weight: 1,
        fillColor: '#7a4fc4', fillOpacity: 0.06, opacity: 0.4,
    }).addTo(layers.dme);
    L.circleMarker([b.lat, b.lon], {
        radius: 5, color: '#7a4fc4', weight: 2, fillColor: '#fff', fillOpacity: 1,
    }).bindTooltip(
        `<div class="dme-tooltip"><b>${b.name}</b> DME/VOR beacon` +
        `<br>Illustrative ${DME_ILLUSTRATIVE_RADIUS_KM}km ring — real cost model is continuous 1/distance, not a cutoff.</div>`,
        { sticky: true }
    ).addTo(layers.dme);
});

// Border hotspots (M2b): sized by crossing count (sqrt scale so the busiest
// pinch point doesn't dwarf everything else on screen).
layers.hotspots = L.layerGroup();
const hotspotCounts = (D.hotspots || []).map((h) => h.count);
const maxHotspotCount = Math.max(1, ...hotspotCounts);
(D.hotspots || []).forEach((h) => {
    const r = 5 + 10 * Math.sqrt(h.count / maxHotspotCount);
    L.circleMarker([h.lat, h.lon], {
        radius: r, color: '#c0392b', weight: 1.5, fillColor: '#c0392b', fillOpacity: 0.35,
    }).bindTooltip(
        `<div class="hotspot-tooltip"><b>${h.ansp_a} &harr; ${h.ansp_b}</b>` +
        `<br>${h.count} confirmed crossings here<br>90% within ${h.km_r90.toFixed(0)}km of centroid</div>`,
        { sticky: true }
    ).addTo(layers.hotspots);
});

bind('t-terrain', layers.terrain);
bind('t-water', layers.water);
bind('t-dme', layers.dme);
bind('t-hotspots', layers.hotspots);
