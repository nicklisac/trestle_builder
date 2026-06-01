// ── Globals ──────────────────────────────────────────────
let scene, camera, renderer, controls;
let trackGroup;
let marbleSphere;
let marblePaths = []; // array of paths for splitter alternation
let marblePathIdx = 0; // which path we're on
let marbleT = 0;
let clock;

// ── Init ─────────────────────────────────────────────────
function init() {
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0f0f23);
    scene.fog = new THREE.Fog(0x0f0f23, 30, 60);

    camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 100);
    camera.position.set(11, 14, 13);

    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    document.getElementById('canvas').appendChild(renderer.domElement);

    controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.target.set(5.5, 3.5, 3);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.minDistance = 5;
    controls.maxDistance = 40;

    // Lighting
    const ambient = new THREE.AmbientLight(0x404060, 0.6);
    scene.add(ambient);

    const dir = new THREE.DirectionalLight(0xffffff, 0.9);
    dir.position.set(8, 15, 10);
    dir.castShadow = true;
    dir.shadow.mapSize.width = 2048;
    dir.shadow.mapSize.height = 2048;
    dir.shadow.camera.near = 0.5;
    dir.shadow.camera.far = 50;
    dir.shadow.camera.left = -15;
    dir.shadow.camera.right = 15;
    dir.shadow.camera.top = 15;
    dir.shadow.camera.bottom = -15;
    scene.add(dir);

    const fill = new THREE.DirectionalLight(0x4488ff, 0.3);
    fill.position.set(-5, 8, -5);
    scene.add(fill);

    // Base plate
    createBase();

    // Track group
    trackGroup = new THREE.Group();
    scene.add(trackGroup);

    // Marble
    const marbleGeo = new THREE.SphereGeometry(0.18, 16, 16);
    const marbleMat = new THREE.MeshStandardMaterial({
        color: 0xff6644, emissive: 0xff2200, emissiveIntensity: 0.5,
        metalness: 0.8, roughness: 0.2
    });
    marbleSphere = new THREE.Mesh(marbleGeo, marbleMat);
    marbleSphere.castShadow = true;
    marbleSphere.visible = false;
    scene.add(marbleSphere);

    clock = new THREE.Clock();

    window.addEventListener('resize', onResize);
    animate();
}

function createBase() {
    // Solid base plate — exactly 10x5 to match grid
    const baseGeo = new THREE.BoxGeometry(10, 0.3, 5);
    const baseMat = new THREE.MeshStandardMaterial({ color: 0x2a2a3e, roughness: 0.8 });
    const base = new THREE.Mesh(baseGeo, baseMat);
    base.position.set(5, -0.15, 2.5);
    base.receiveShadow = true;
    scene.add(base);

    // Grid lines on top of base
    const points = [];
    for (let z = 0; z <= 5; z++) {
        points.push(new THREE.Vector3(0, 0.01, z), new THREE.Vector3(10, 0.01, z));
    }
    for (let x = 0; x <= 10; x++) {
        points.push(new THREE.Vector3(x, 0.01, 0), new THREE.Vector3(x, 0.01, 5));
    }
    const gridGeo = new THREE.BufferGeometry().setFromPoints(points);
    const gridMat = new THREE.LineBasicMaterial({ color: 0x444466 });
    const grid = new THREE.LineSegments(gridGeo, gridMat);
    scene.add(grid);

    // 5x5 division line
    const divPoints = [
        new THREE.Vector3(5, 0.02, 0), new THREE.Vector3(5, 0.02, 5)
    ];
    const divGeo = new THREE.BufferGeometry().setFromPoints(divPoints);
    const divMat = new THREE.LineBasicMaterial({ color: 0x666688 });
    scene.add(new THREE.LineSegments(divGeo, divMat));
}

// ── Coordinate mapping: our (x, y, z) → Three.js (x+0.5, z, y+0.5) ──
// +0.5 on x and z centers pieces/towers in grid squares instead of on grid lines
function to3(x, y, z) {
    return new THREE.Vector3(x + 0.5, z, y + 0.5);
}

// ── Piece color palette ──────────────────────────────────
function pieceColor(pieceId, total) {
    const hue = ((pieceId - 1) / Math.max(total, 1)) * 360;
    return new THREE.Color(`hsl(${hue}, 72%, 52%)`);
}

// ── Clear track ──────────────────────────────────────────
function clearTrack() {
    while (trackGroup.children.length > 0) {
        const obj = trackGroup.children[0];
        if (obj.geometry) obj.geometry.dispose();
        if (obj.material) {
            if (Array.isArray(obj.material)) obj.material.forEach(m => m.dispose());
            else obj.material.dispose();
        }
        trackGroup.remove(obj);
    }
    marblePaths = [];
    marblePathIdx = 0;
    marbleT = 0;
    marbleSphere.visible = false;
}

// ── Render solution ──────────────────────────────────────
function renderTrack(solution) {
    clearTrack();

    const pieces = solution.pieces;
    const total = pieces.length;

    // ── Tower risers: only at start/end support positions ──
    const riserGeo = new THREE.BoxGeometry(0.35, 0.95, 0.35);
    const riserMat = new THREE.MeshStandardMaterial({ color: 0x8B7355, roughness: 0.7 });
    // Towers ONLY at start/end support positions (shared if same x,y different z)
    const supportMaxZ = {};
    pieces.forEach(p => {
        [p.start, p.end].forEach(pt => {
            const key = `${pt[0]},${pt[1]}`;
            supportMaxZ[key] = Math.max(supportMaxZ[key] || 0, pt[2]);
        });
    });
    // Shift risers up 0.5 so bottom riser sits on base surface (y=0) instead of penetrating through
    const riserYOffset = 0.5;
    for (const [key, maxZ] of Object.entries(supportMaxZ)) {
        const [tx, ty] = key.split(',').map(Number);
        for (let z = 0; z < maxZ; z++) {
            const riser = new THREE.Mesh(riserGeo, riserMat);
            const pos = to3(tx, ty, z);
            pos.y += riserYOffset;
            riser.position.copy(pos);
            riser.castShadow = true;
            riser.receiveShadow = true;
            trackGroup.add(riser);
        }
    }

    // ── Piece cells: thin plates sitting on top of risers ──
    const cellGeo = new THREE.BoxGeometry(0.92, 0.1, 0.92);
    // Plate sits on top of risers (which are shifted up 0.5): center at z+0.025
    const plateYOffset = 0.025;

    pieces.forEach((p, idx) => {
        const color = pieceColor(p.piece_id, total);
        const mat = new THREE.MeshStandardMaterial({
            color, roughness: 0.35, metalness: 0.15
        });

        p.cells.forEach(cell => {
            const cube = new THREE.Mesh(cellGeo, mat);
            const pos = to3(cell[0], cell[1], cell[2]);
            pos.y += plateYOffset;
            cube.position.copy(pos);
            cube.castShadow = true;
            cube.receiveShadow = true;
            trackGroup.add(cube);
        });

        // Cell border edges
        const edgeGeo = new THREE.EdgesGeometry(cellGeo);
        const edgeMat = new THREE.LineBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.15 });
        p.cells.forEach(cell => {
            const edges = new THREE.LineSegments(edgeGeo, edgeMat);
            const pos = to3(cell[0], cell[1], cell[2]);
            pos.y += plateYOffset;
            edges.position.copy(pos);
            trackGroup.add(edges);
        });
    });

    // ── Entry / Exit markers ──
    const chains = traceChains(pieces);
    chains.forEach(chain => {
        if (chain.length === 0) return;

        // Entry marker (green cone above first piece start)
        const entry = chain[0];
        const entryPos = to3(entry.start[0], entry.start[1], entry.start[2]);
        entryPos.y += plateYOffset;
        addMarker(entryPos.clone().add(new THREE.Vector3(0, 0.5, 0)), 0x44ff44, true);

        // Find exit(s)
        const exits = findExits(chain);
        exits.forEach(exitPiece => {
            const exitPos = to3(exitPiece.end[0], exitPiece.end[1], exitPiece.end[2]);
            exitPos.y += plateYOffset;
            addMarker(exitPos.clone().add(new THREE.Vector3(0, -0.5, 0)), 0xff4444, false);
        });
    });

    // Marble path: trace all chains with splitter flip-flop alternation
    const allLookup = {};
    pieces.forEach(p => {
        const key = `${p.start[0]},${p.start[1]},${p.start[2]}`;
        allLookup[key] = p;
    });
    // Augment traceMarblePath with full lookup
    const _origFollow = followChainFromSocket;
    chains.forEach(chain => {
        if (chain.length === 0) return;
        const splitterIdx = chain.findIndex(p => p.is_splitter);
        if (splitterIdx < 0) {
            marblePaths.push(buildPathPoints(chain));
            return;
        }
        const splitter = chain[splitterIdx];
        const stem = chain.slice(0, splitterIdx + 1);
        const stemPts = buildPathPoints(stem);
        splitter.outputs.forEach(out => {
            const socketKey = `${out[0]},${out[1]},${out[2] - 1}`;
            const branch = [];
            followChainFromSocket(socketKey, allLookup, new Set(), branch);
            if (branch.length > 0) {
                marblePaths.push([...stemPts, ...buildPathPoints(branch)]);
            }
        });
    });
    if (marblePaths.length === 0) {
        marblePaths = [buildPathPoints(chains.flat())];
    }

    // ── Connection drop lines ──
    const dropMat = new THREE.LineDashedMaterial({
        color: 0xff8844, dashSize: 0.15, gapSize: 0.1,
        transparent: true, opacity: 0.6
    });

    pieces.forEach(p => {
        const endPos = to3(p.end[0], p.end[1], p.end[2]);
        endPos.y += plateYOffset;
        const nextSocket = to3(p.end[0], p.end[1], p.end[2] - 1);
        nextSocket.y += plateYOffset;

        if (p.is_splitter) {
            p.outputs.forEach(out => {
                const outPos = to3(out[0], out[1], out[2]);
                outPos.y += plateYOffset;
                const outSocket = to3(out[0], out[1], out[2] - 1);
                outSocket.y += plateYOffset;
                const points = [outPos, outSocket];
                const geo = new THREE.BufferGeometry().setFromPoints(points);
                const line = new THREE.Line(geo, dropMat);
                line.computeLineDistances();
                trackGroup.add(line);
            });
        } else {
            const points = [endPos, nextSocket];
            const geo = new THREE.BufferGeometry().setFromPoints(points);
            const line = new THREE.Line(geo, dropMat);
            line.computeLineDistances();
            trackGroup.add(line);
        }
    });

    // ── Update UI ──
    document.getElementById('info').innerHTML =
        `<span>${total}</span> pieces &middot; <span>${solution.tower_count}</span> towers &middot; seed <span>${document.getElementById('seed').value || 'random'}</span>`;

    // Legend
    const legendEl = document.getElementById('legend');
    const legendItems = document.getElementById('legend-items');
    legendItems.innerHTML = '';
    pieces.forEach(p => {
        const c = pieceColor(p.piece_id, total);
        const hex = '#' + c.getHexString();
        const item = document.createElement('div');
        item.className = 'legend-item';
        const tag = p.is_splitter ? ' [SPLIT]' : (p.end[2] !== p.start[2] ? ' [DESC]' : '');
        item.innerHTML = `<div class="legend-color" style="background:${hex}"></div><span class="legend-label">P${p.piece_id}${tag} z=${p.origin[2]}</span>`;
        legendItems.appendChild(item);
    });
    legendEl.style.display = 'block';

    // Chain info
    const chainEl = document.getElementById('chain-info');
    const chainText = document.getElementById('chain-text');
    const chainStrs = chains.map(c => c.map(p => `P${p.piece_id}`).join(' -> '));
    chainText.innerHTML = chainStrs.map(s => `<p>${s}</p>`).join('');
    chainEl.style.display = 'block';

    // Camera: frame the track
    if (total > 0) {
        const maxZ = Math.max(...pieces.map(p => p.origin[2]));
        controls.target.set(5.5, maxZ * 0.45 + 0.5, 3);
        camera.position.set(11, maxZ + 6.5, 13);
        controls.update();
    }
}

// ── Marker (cone) ────────────────────────────────────────
function addMarker(position, color, up) {
    const geo = new THREE.ConeGeometry(0.22, 0.55, 8);
    const mat = new THREE.MeshStandardMaterial({
        color, emissive: color, emissiveIntensity: 0.4
    });
    const cone = new THREE.Mesh(geo, mat);
    cone.position.copy(position);
    if (!up) cone.rotation.x = Math.PI;
    cone.castShadow = true;
    trackGroup.add(cone);
}

// ── Chain tracing ────────────────────────────────────────
function traceChains(pieces) {
    const lookup = {};
    pieces.forEach(p => {
        const key = `${p.start[0]},${p.start[1]},${p.start[2]}`;
        lookup[key] = p;
    });

    const nextSockets = new Set();
    pieces.forEach(p => {
        nextSockets.add(`${p.end[0]},${p.end[1]},${p.end[2] - 1}`);
        if (p.is_splitter) {
            p.outputs.forEach(o => nextSockets.add(`${o[0]},${o[1]},${o[2] - 1}`));
        }
    });

    const entries = pieces.filter(p => !nextSockets.has(`${p.start[0]},${p.start[1]},${p.start[2]}`));
    const chains = [];

    entries.forEach(entry => {
        const chain = [];
        followChain(entry, lookup, new Set(), chain);
        chains.push(chain);
    });

    return chains;
}

function followChain(piece, lookup, visited, chain) {
    if (visited.has(piece.piece_id)) return;
    visited.add(piece.piece_id);
    chain.push(piece);

    if (piece.is_splitter) {
        // Splitter: don't follow further in linear chain
        return;
    }

    const key = `${piece.end[0]},${piece.end[1]},${piece.end[2] - 1}`;
    const next = lookup[key];
    if (next && !visited.has(next.piece_id)) {
        followChain(next, lookup, visited, chain);
    }
}

function findExits(chain) {
    const exits = [];
    const lookup = {};
    // Build lookup from all pieces in chain
    chain.forEach(p => {
        const key = `${p.start[0]},${p.start[1]},${p.start[2]}`;
        lookup[key] = p;
    });

    // Last piece in chain is an exit (or splitter)
    if (chain.length > 0) {
        const last = chain[chain.length - 1];
        exits.push(last);
    }
    return exits;
}

// ── Marble path for animation ────────────────────────────
function buildPathPoints(pieceChain) {
    const pts = [];
    pieceChain.forEach(p => {
        const s = to3(p.start[0], p.start[1], p.start[2]);
        const e = to3(p.end[0], p.end[1], p.end[2]);
        s.y += 0.025;
        e.y += 0.025;
        pts.push(s, e);
    });
    return pts;
}

function followChainFromSocket(socketKey, lookup, visited, chain) {
    const next = lookup[socketKey];
    if (!next || visited.has(next.piece_id)) return;
    visited.add(next.piece_id);
    chain.push(next);
    if (next.is_splitter) return;
    const nextKey = `${next.end[0]},${next.end[1]},${next.end[2] - 1}`;
    followChainFromSocket(nextKey, lookup, visited, chain);
}

// ── Animation loop ───────────────────────────────────────
function animate() {
    requestAnimationFrame(animate);
    const delta = clock.getDelta();

    controls.update();

    // Animate marble along path with splitter alternation
    if (marblePaths.length > 0 && marblePaths[0].length >= 2) {
        marbleSphere.visible = true;
        const currentPath = marblePaths[marblePathIdx % marblePaths.length];
        const totalSegments = currentPath.length - 1;
        const speed = 0.3;
        marbleT += delta * speed;

        if (marbleT > totalSegments) {
            marbleT = 0;
            marblePathIdx++; // switch to alternate path (splitter flip-flop)
        }

        const seg = Math.floor(marbleT);
        const t = marbleT - seg;
        const idx = Math.min(seg, totalSegments - 1);

        const from = currentPath[idx];
        const to = currentPath[idx + 1];
        marbleSphere.position.lerpVectors(from, to, t);
        marbleSphere.position.y += 0.22; // float above thin plates
    }

    renderer.render(scene, camera);
}

function onResize() {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
}

// ── API calls ────────────────────────────────────────────
async function solve(seed) {
    const btn = document.getElementById('btn-gen');
    const loading = document.getElementById('loading');
    btn.disabled = true;
    loading.style.display = 'inline';

    try {
        const url = seed !== null
            ? `/api/solve?seed=${seed}&max_towers=100&timeout=30`
            : `/api/solve?max_towers=100&timeout=30`;

        const resp = await fetch(url);
        const data = await resp.json();

        if (data.found && data.solution) {
            renderTrack(data.solution);
        } else {
            document.getElementById('info').innerHTML = 'No solution found. Try another seed.';
        }
    } catch (e) {
        console.error(e);
        document.getElementById('info').innerHTML = 'Error solving. Check console.';
    }

    btn.disabled = false;
    loading.style.display = 'none';
}

// ── Event listeners ──────────────────────────────────────
document.getElementById('btn-gen').addEventListener('click', () => {
    const seedVal = document.getElementById('seed').value;
    const seed = seedVal !== '' ? parseInt(seedVal) : null;
    solve(seed);
});

document.getElementById('btn-rand').addEventListener('click', () => {
    const seed = Math.floor(Math.random() * 1000000);
    document.getElementById('seed').value = seed;
    solve(seed);
});

document.getElementById('seed').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        const seedVal = document.getElementById('seed').value;
        const seed = seedVal !== '' ? parseInt(seedVal) : null;
        solve(seed);
    }
});

// ── Start ────────────────────────────────────────────────
init();
