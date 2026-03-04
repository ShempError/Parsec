// Parsec Texture Generator
// Generates minimap icon, banner, 21 UI icons, and 4 bar textures
// Run: node tools/generate-textures.js

const fs = require('fs');
const path = require('path');

const TEXTURES_DIR = path.join(__dirname, '..', 'textures');

// --- TGA Writer (32-bit BGRA uncompressed) ---
function writeTGA(filepath, width, height, pixels) {
    const header = Buffer.alloc(18);
    header[2] = 2;
    header.writeUInt16LE(width, 12);
    header.writeUInt16LE(height, 14);
    header[16] = 32;
    header[17] = 0x08; // bottom-up origin (standard TGA), 8 alpha bits

    // Write rows bottom-to-top (standard TGA row order)
    const imageData = Buffer.alloc(width * height * 4);
    for (let y = 0; y < height; y++) {
        const outY = height - 1 - y; // flip: source top row -> TGA bottom row
        for (let x = 0; x < width; x++) {
            const srcIdx = (y * width + x) * 4;
            const dstIdx = (outY * width + x) * 4;
            imageData[dstIdx + 0] = pixels[srcIdx + 2]; // B
            imageData[dstIdx + 1] = pixels[srcIdx + 1]; // G
            imageData[dstIdx + 2] = pixels[srcIdx + 0]; // R
            imageData[dstIdx + 3] = pixels[srcIdx + 3]; // A
        }
    }

    fs.writeFileSync(filepath, Buffer.concat([header, imageData]));
    console.log(`  ${path.basename(filepath)} (${width}x${height})`);
}

// --- Helpers ---
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
function smoothstep(e0, e1, x) { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); }

// Create pixel buffer, call draw(x, y, setPixel), return pixels
function renderIcon(w, h, drawFn) {
    const px = new Uint8Array(w * h * 4);
    const set = (x, y, r, g, b, a) => {
        if (x < 0 || x >= w || y < 0 || y >= h) return;
        const i = (y * w + x) * 4;
        px[i] = clamp(Math.round(r), 0, 255);
        px[i+1] = clamp(Math.round(g), 0, 255);
        px[i+2] = clamp(Math.round(b), 0, 255);
        px[i+3] = clamp(Math.round(a), 0, 255);
    };
    const blend = (x, y, r, g, b, a) => {
        if (x < 0 || x >= w || y < 0 || y >= h) return;
        const i = (y * w + x) * 4;
        const oa = px[i+3] / 255;
        const na = a / 255;
        const fa = na + oa * (1 - na);
        if (fa === 0) return;
        px[i] = clamp(Math.round((r * na + px[i] * oa * (1 - na)) / fa), 0, 255);
        px[i+1] = clamp(Math.round((g * na + px[i+1] * oa * (1 - na)) / fa), 0, 255);
        px[i+2] = clamp(Math.round((b * na + px[i+2] * oa * (1 - na)) / fa), 0, 255);
        px[i+3] = clamp(Math.round(fa * 255), 0, 255);
    };
    drawFn(w, h, set, blend);
    return px;
}

// Cyan accent color
const C = [0, 204, 255];
const CW = [180, 230, 255]; // lighter cyan-white

// Draw a line using Bresenham
function drawLine(x0, y0, x1, y1, set, r, g, b, a) {
    x0 = Math.round(x0); y0 = Math.round(y0);
    x1 = Math.round(x1); y1 = Math.round(y1);
    const dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx - dy;
    while (true) {
        set(x0, y0, r, g, b, a);
        if (x0 === x1 && y0 === y1) break;
        const e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 < dx) { err += dx; y0 += sy; }
    }
}

// Draw circle outline
function drawCircle(cx, cy, radius, set, r, g, b, a) {
    for (let angle = 0; angle < 360; angle += 2) {
        const rad = angle * Math.PI / 180;
        const x = Math.round(cx + radius * Math.cos(rad));
        const y = Math.round(cy + radius * Math.sin(rad));
        set(x, y, r, g, b, a);
    }
}

// Fill circle
function fillCircle(cx, cy, radius, set, r, g, b, a) {
    for (let y = Math.floor(cy - radius); y <= Math.ceil(cy + radius); y++) {
        for (let x = Math.floor(cx - radius); x <= Math.ceil(cx + radius); x++) {
            const dx = x - cx, dy = y - cy;
            if (dx * dx + dy * dy <= radius * radius) set(x, y, r, g, b, a);
        }
    }
}

// Draw filled rectangle
function fillRect(x0, y0, x1, y1, set, r, g, b, a) {
    for (let y = Math.round(y0); y <= Math.round(y1); y++)
        for (let x = Math.round(x0); x <= Math.round(x1); x++)
            set(x, y, r, g, b, a);
}

// =====================================================================
// MINIMAP ICON (64x64) - existing starburst design
// =====================================================================
function generateIcon() {
    const W = 64, H = 64;
    const pixels = new Uint8Array(W * H * 4);
    const cx = (W - 1) / 2, cy = (H - 1) / 2;
    const outerR = 29;
    const CYAN = [0, 204, 255];
    const BG_DARK = [8, 12, 24];
    const BG_MID = [14, 22, 44];

    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const dx = x - cx, dy = y - cy;
            const dist = Math.sqrt(dx * dx + dy * dy);
            const angle = Math.atan2(dy, dx);
            if (dist > outerR + 1) { continue; }
            const edgeAlpha = clamp(outerR + 0.5 - dist, 0, 1);
            const bgT = clamp(dist / outerR, 0, 1);
            let r = BG_MID[0] + (BG_DARK[0] - BG_MID[0]) * bgT;
            let g = BG_MID[1] + (BG_DARK[1] - BG_MID[1]) * bgT;
            let b = BG_MID[2] + (BG_DARK[2] - BG_MID[2]) * bgT;
            let starI = 0;
            for (let i = 0; i < 4; i++) {
                const ra = i * Math.PI / 2 - Math.PI / 2;
                let ad = Math.abs(angle - ra); if (ad > Math.PI) ad = 2 * Math.PI - ad;
                const rw = 0.18 * (1 - dist / outerR * 0.6);
                const rf = clamp(1 - ad / Math.max(rw, 0.01), 0, 1);
                starI = Math.max(starI, Math.pow(Math.max(0, 1 - dist / outerR), 0.4) * Math.pow(rf, 1.5));
            }
            for (let i = 0; i < 4; i++) {
                const ra = i * Math.PI / 2 + Math.PI / 4 - Math.PI / 2;
                let ad = Math.abs(angle - ra); if (ad > Math.PI) ad = 2 * Math.PI - ad;
                const rw = 0.09 * (1 - dist / outerR * 0.7);
                const rf = clamp(1 - ad / Math.max(rw, 0.01), 0, 1);
                starI = Math.max(starI, Math.pow(Math.max(0, 1 - dist / outerR), 0.5) * Math.pow(rf, 1.5) * 0.55);
            }
            const coreGlow = Math.pow(Math.max(0, 1 - dist / 7), 2.5);
            const innerGlow = Math.pow(Math.max(0, 1 - dist / 15), 1.8) * 0.4;
            r += (CYAN[0] - r) * starI; g += (CYAN[1] - g) * starI; b += (CYAN[2] - b) * starI;
            r += (CYAN[0] - r) * innerGlow; g += (CYAN[1] - g) * innerGlow; b += (CYAN[2] - b) * innerGlow;
            r += (255 - r) * coreGlow; g += (255 - g) * coreGlow; b += (255 - b) * coreGlow;
            const borderDist = Math.abs(dist - outerR + 1.5);
            const borderI = clamp(1 - borderDist / 1.2, 0, 1) * 0.5;
            r += (CYAN[0] - r) * borderI; g += (CYAN[1] - g) * borderI; b += (CYAN[2] - b) * borderI;
            const seed = ((x * 127 + y * 311) ^ (x * 7 + y * 53)) % 1000;
            if (seed < 12 && dist > 12 && dist < outerR - 3 && starI < 0.08) {
                const sB = 0.25 + (seed % 5) * 0.12;
                r = clamp(r + 150 * sB, 0, 255); g = clamp(g + 170 * sB, 0, 255); b = clamp(b + 220 * sB, 0, 255);
            }
            const idx = (y * W + x) * 4;
            pixels[idx] = clamp(Math.round(r), 0, 255);
            pixels[idx+1] = clamp(Math.round(g), 0, 255);
            pixels[idx+2] = clamp(Math.round(b), 0, 255);
            pixels[idx+3] = Math.round(edgeAlpha * 255);
        }
    }
    writeTGA(path.join(TEXTURES_DIR, 'icon.tga'), W, H, pixels);
}

// =====================================================================
// BANNER (256x64) - existing space background
// =====================================================================
function generateBanner() {
    const W = 256, H = 64;
    const pixels = new Uint8Array(W * H * 4);
    const BG_TOP = [6, 10, 22], BG_BOT = [12, 18, 36];

    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const vt = y / (H - 1);
            let r = BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * vt;
            let g = BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * vt;
            let b = BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * vt;
            const ht = Math.abs(x - W / 2) / (W / 2);
            const vig = 1 - ht * ht * 0.3;
            r *= vig; g *= vig; b *= vig;
            const gdx = (x - W/2) / 100, gdy = (y - H/2 + 4) / 28;
            const glI = Math.pow(Math.max(0, 1 - Math.sqrt(gdx*gdx+gdy*gdy)), 2) * 0.12;
            r += (C[0]-r)*glI; g += (C[1]-g)*glI; b += (C[2]-b)*glI;
            if (y <= 1) { const li = (1 - ht) * (y === 0 ? 0.6 : 0.25); r += (C[0]-r)*li; g += (C[1]-g)*li; b += (C[2]-b)*li; }
            if (y >= H-2) { const li = (1 - ht) * (y === H-1 ? 0.6 : 0.25); r += (C[0]-r)*li; g += (C[1]-g)*li; b += (C[2]-b)*li; }
            const seed = ((x * 191 + y * 277) ^ (x * 13 + y * 41)) % 1000;
            if (seed < 8 && y > 3 && y < H-3) {
                const sB = 0.2 + (seed % 6) * 0.1;
                r = clamp(r+120*sB, 0, 255); g = clamp(g+140*sB, 0, 255); b = clamp(b+200*sB, 0, 255);
            }
            for (const sx of [0.15, 0.85]) {
                if (x === Math.floor(W*sx)) {
                    const fy = 1 - Math.abs(y-H/2)/(H/2); const li = fy*fy*0.2;
                    r += (C[0]-r)*li; g += (C[1]-g)*li; b += (C[2]-b)*li;
                }
            }
            const cs = 8, ci = 0.35;
            if ((x < cs && y === 2) || (x === 2 && y < cs)) { r += (C[0]-r)*ci; g += (C[1]-g)*ci; b += (C[2]-b)*ci; }
            if ((x > W-cs-1 && y === 2) || (x === W-3 && y < cs)) { r += (C[0]-r)*ci; g += (C[1]-g)*ci; b += (C[2]-b)*ci; }
            if ((x < cs && y === H-3) || (x === 2 && y > H-cs-1)) { r += (C[0]-r)*ci; g += (C[1]-g)*ci; b += (C[2]-b)*ci; }
            if ((x > W-cs-1 && y === H-3) || (x === W-3 && y > H-cs-1)) { r += (C[0]-r)*ci; g += (C[1]-g)*ci; b += (C[2]-b)*ci; }
            const idx = (y * W + x) * 4;
            pixels[idx] = clamp(Math.round(r), 0, 255);
            pixels[idx+1] = clamp(Math.round(g), 0, 255);
            pixels[idx+2] = clamp(Math.round(b), 0, 255);
            pixels[idx+3] = 255;
        }
    }
    writeTGA(path.join(TEXTURES_DIR, 'banner.tga'), W, H, pixels);
}

// =====================================================================
// 16x16 SETTINGS ICONS (for checkboxes)
// =====================================================================

// Eye icon - Auto-Show
function genIconEye() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Eye shape: ellipse outline + filled circle pupil
        const cx = 7.5, cy = 7.5;
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
            const dx = (x - cx) / 6, dy = (y - cy) / 3;
            const d = dx*dx + dy*dy;
            // Eye outline
            if (d > 0.6 && d < 1.2) set(x, y, C[0], C[1], C[2], 200);
            // Pupil
            const pd = (x-cx)*(x-cx) + (y-cy)*(y-cy);
            if (pd < 5) set(x, y, CW[0], CW[1], CW[2], 255);
            else if (pd < 9) set(x, y, C[0], C[1], C[2], 220);
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-eye.tga'), s, s, px);
}

// Eye-closed icon - Auto-Hide
function genIconEyeClosed() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        const cx = 7.5, cy = 7.5;
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
            // Closed eye - bottom half of ellipse + horizontal line
            const dx = (x - cx) / 6, dy = (y - cy - 1) / 3;
            const d = dx*dx + dy*dy;
            if (d > 0.6 && d < 1.2 && y >= 7) set(x, y, C[0], C[1], C[2], 200);
            // Horizontal line at eye center
            if (y >= 7 && y <= 8 && x >= 2 && x <= 13) set(x, y, C[0], C[1], C[2], 220);
            // Diagonal slash
            if (Math.abs(x - y) <= 0 && x >= 3 && x <= 12) set(x, y, CW[0], CW[1], CW[2], 180);
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-eye-closed.tga'), s, s, px);
}

// Lock icon - Lock Windows
function genIconLock() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Lock body (rectangle)
        fillRect(4, 8, 11, 14, set, C[0], C[1], C[2], 220);
        // Lock shackle (arc)
        for (let angle = 180; angle <= 360; angle += 3) {
            const rad = angle * Math.PI / 180;
            const x = Math.round(7.5 + 3 * Math.cos(rad));
            const y = Math.round(8 + 3.5 * Math.sin(rad));
            set(x, y, C[0], C[1], C[2], 220);
            set(x+1, y, C[0], C[1], C[2], 220);
        }
        // Keyhole
        fillCircle(7.5, 10.5, 1.2, set, 10, 15, 30, 255);
        set(7, 12, 10, 15, 30, 255); set(8, 12, 10, 15, 30, 255);
        set(7, 13, 10, 15, 30, 255); set(8, 13, 10, 15, 30, 255);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-lock.tga'), s, s, px);
}

// Minimap icon - compass/radar shape
function genIconMinimap() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        const cx = 7.5, cy = 7.5;
        drawCircle(cx, cy, 6, set, C[0], C[1], C[2], 200);
        // Cross-hairs
        drawLine(7, 1, 7, 4, set, C[0], C[1], C[2], 160);
        drawLine(7, 11, 7, 14, set, C[0], C[1], C[2], 160);
        drawLine(1, 7, 4, 7, set, C[0], C[1], C[2], 160);
        drawLine(11, 7, 14, 7, set, C[0], C[1], C[2], 160);
        // Center dot
        fillCircle(cx, cy, 1.5, set, CW[0], CW[1], CW[2], 255);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-minimap.tga'), s, s, px);
}

// Merge icon - two arrows merging into one
function genIconMerge() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Two arrows from left converging to right
        drawLine(1, 4, 8, 7, set, C[0], C[1], C[2], 220);
        drawLine(1, 11, 8, 8, set, C[0], C[1], C[2], 220);
        drawLine(8, 7, 14, 7, set, CW[0], CW[1], CW[2], 255);
        drawLine(8, 8, 14, 8, set, CW[0], CW[1], CW[2], 255);
        // Arrow head
        drawLine(12, 5, 14, 7, set, CW[0], CW[1], CW[2], 255);
        drawLine(12, 10, 14, 8, set, CW[0], CW[1], CW[2], 255);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-merge.tga'), s, s, px);
}

// Group icon - two people silhouettes
function genIconGroup() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Person 1 (front)
        fillCircle(6, 4, 2, set, CW[0], CW[1], CW[2], 240);
        fillRect(3, 8, 9, 14, set, C[0], C[1], C[2], 200);
        // Person 2 (behind, offset right)
        fillCircle(11, 3, 1.8, set, C[0], C[1], C[2], 160);
        fillRect(8, 7, 13, 13, set, C[0]*0.6, C[1]*0.6, C[2]*0.6, 140);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-group.tga'), s, s, px);
}

// Palette icon - color swatch
function genIconPalette() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Paint palette shape (circle with holes)
        const cx = 7.5, cy = 8;
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
            const dx = x - cx, dy = y - cy;
            const d = Math.sqrt(dx*dx + dy*dy);
            if (d < 7 && d > 5.5) set(x, y, C[0], C[1], C[2], 200);
            if (d <= 5.5) set(x, y, C[0]*0.3, C[1]*0.3, C[2]*0.3, 160);
        }
        // Color dots on palette
        fillCircle(5, 5, 1.2, set, 220, 100, 100, 255);
        fillCircle(9, 4, 1.2, set, 100, 220, 100, 255);
        fillCircle(11, 7, 1.2, set, 100, 100, 220, 255);
        fillCircle(9, 11, 1.2, set, 220, 200, 80, 255);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-palette.tga'), s, s, px);
}

// Backdrop icon - framed window
function genIconBackdrop() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Outer frame
        fillRect(1, 1, 14, 14, set, C[0], C[1], C[2], 200);
        // Inner dark area
        fillRect(3, 3, 12, 12, set, 10, 15, 30, 240);
        // Gradient hint inside
        for (let y = 3; y <= 12; y++) {
            const t = (y - 3) / 9;
            const a = 60 + t * 60;
            for (let x = 3; x <= 12; x++) set(x, y, C[0]*0.15, C[1]*0.15, C[2]*0.15, a);
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-backdrop.tga'), s, s, px);
}

// =====================================================================
// 16x16 SIDEBAR ICONS (for options categories)
// =====================================================================

// General icon - gear/cog
function genIconGeneral() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        const cx = 7.5, cy = 7.5;
        // Gear teeth
        for (let i = 0; i < 8; i++) {
            const angle = i * Math.PI / 4;
            const x1 = cx + 5 * Math.cos(angle), y1 = cy + 5 * Math.sin(angle);
            const x2 = cx + 7 * Math.cos(angle), y2 = cy + 7 * Math.sin(angle);
            drawLine(Math.round(x1), Math.round(y1), Math.round(x2), Math.round(y2), set, C[0], C[1], C[2], 220);
        }
        // Outer ring
        drawCircle(cx, cy, 5, set, C[0], C[1], C[2], 220);
        // Inner ring
        drawCircle(cx, cy, 2.5, set, CW[0], CW[1], CW[2], 240);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-general.tga'), s, s, px);
}

// Windows icon - overlapping windows
function genIconWindows() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Back window
        fillRect(4, 1, 14, 10, set, C[0]*0.5, C[1]*0.5, C[2]*0.5, 160);
        drawLine(4, 1, 14, 1, set, C[0], C[1], C[2], 180);
        drawLine(4, 1, 4, 10, set, C[0], C[1], C[2], 180);
        drawLine(14, 1, 14, 10, set, C[0], C[1], C[2], 180);
        drawLine(4, 10, 14, 10, set, C[0], C[1], C[2], 180);
        // Front window
        fillRect(1, 5, 11, 14, set, 10, 15, 30, 220);
        drawLine(1, 5, 11, 5, set, CW[0], CW[1], CW[2], 240);
        drawLine(1, 5, 1, 14, set, C[0], C[1], C[2], 220);
        drawLine(11, 5, 11, 14, set, C[0], C[1], C[2], 220);
        drawLine(1, 14, 11, 14, set, C[0], C[1], C[2], 220);
        // Title bar highlight
        fillRect(1, 5, 11, 7, set, C[0]*0.3, C[1]*0.3, C[2]*0.3, 200);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-windows.tga'), s, s, px);
}

// Automation icon - lightning bolt
function genIconAutomation() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Lightning bolt shape
        const pts = [[9,1],[4,7],[7,7],[5,14],[12,6],[8,6],[10,1]];
        // Fill the bolt
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
            // Simple point-in-polygon for the bolt shape
            let inside = false;
            for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
                const [xi, yi] = pts[i], [xj, yj] = pts[j];
                if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
            }
            if (inside) set(x, y, CW[0], CW[1], CW[2], 240);
        }
        // Outline
        for (let i = 0; i < pts.length; i++) {
            const j = (i + 1) % pts.length;
            drawLine(pts[i][0], pts[i][1], pts[j][0], pts[j][1], set, C[0], C[1], C[2], 255);
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-automation.tga'), s, s, px);
}

// About icon - info "i" in circle
function genIconAbout() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        const cx = 7.5, cy = 7.5;
        drawCircle(cx, cy, 6.5, set, C[0], C[1], C[2], 200);
        // Dot on the i
        fillCircle(7.5, 4, 1, set, CW[0], CW[1], CW[2], 255);
        // Stem of the i
        fillRect(7, 6, 8, 12, set, CW[0], CW[1], CW[2], 240);
        // Serifs
        fillRect(5, 6, 10, 6, set, C[0], C[1], C[2], 180);
        fillRect(5, 12, 10, 12, set, C[0], C[1], C[2], 180);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-about.tga'), s, s, px);
}

// =====================================================================
// 16x16 TITLE BAR ICONS (for window buttons)
// =====================================================================

// Settings gear (small)
function genIconSettings() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        const cx = 7.5, cy = 7.5;
        for (let i = 0; i < 6; i++) {
            const a = i * Math.PI / 3;
            const x1 = cx + 4.7*Math.cos(a), y1 = cy + 4.7*Math.sin(a);
            const x2 = cx + 6.7*Math.cos(a), y2 = cy + 6.7*Math.sin(a);
            drawLine(Math.round(x1), Math.round(y1), Math.round(x2), Math.round(y2), set, C[0], C[1], C[2], 220);
        }
        drawCircle(cx, cy, 4.7, set, C[0], C[1], C[2], 200);
        drawCircle(cx, cy, 2, set, CW[0], CW[1], CW[2], 230);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-settings.tga'), s, s, px);
}

// Reset - circular arrow
function genIconReset() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        const cx = 7.5, cy = 7.5;
        // Arc (270 degrees)
        for (let angle = 30; angle <= 330; angle += 3) {
            const rad = angle * Math.PI / 180;
            const x = Math.round(cx + 5.3 * Math.cos(rad));
            const y = Math.round(cy + 5.3 * Math.sin(rad));
            set(x, y, C[0], C[1], C[2], 220);
        }
        // Arrow head at end of arc
        drawLine(11, 1, 13, 4, set, CW[0], CW[1], CW[2], 255);
        drawLine(13, 1, 13, 4, set, CW[0], CW[1], CW[2], 255);
        set(12, 3, CW[0], CW[1], CW[2], 255);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-reset.tga'), s, s, px);
}

// Announce - megaphone
function genIconAnnounce() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Megaphone body (trapezoid)
        for (let x = 2; x <= 9; x++) {
            const spread = (x - 2) * 0.6;
            const top = Math.round(5 - spread);
            const bot = Math.round(10 + spread);
            for (let y = top; y <= bot; y++) set(x, y, C[0], C[1], C[2], 210);
        }
        // Sound waves
        for (let i = 0; i < 3; i++) {
            const cx = 10 + i;
            for (let y = 4; y <= 11; y++) {
                const dy = y - 7.5;
                if (Math.abs(dy) < 2.7 + i * 1) set(cx, y, CW[0], CW[1], CW[2], 180 - i * 40);
            }
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-announce.tga'), s, s, px);
}

// View-Damage - sword
function genIconViewDamage() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Blade (diagonal)
        drawLine(3, 12, 12, 3, set, CW[0], CW[1], CW[2], 255);
        drawLine(4, 12, 12, 4, set, C[0], C[1], C[2], 200);
        // Hilt
        drawLine(1, 11, 5, 15, set, C[0], C[1], C[2], 220);
        // Cross-guard
        drawLine(5, 8, 8, 11, set, C[0], C[1], C[2], 200);
        // Tip glow
        set(12, 3, 255, 255, 255, 255);
        set(13, 2, CW[0], CW[1], CW[2], 180);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-view-damage.tga'), s, s, px);
}

// View-Healing - plus/cross
function genIconViewHealing() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Green cross
        fillRect(5, 2, 10, 13, set, 80, 220, 100, 240);
        fillRect(2, 5, 13, 10, set, 80, 220, 100, 240);
        // Brighter center
        fillRect(5, 5, 10, 10, set, 120, 255, 140, 255);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-view-healing.tga'), s, s, px);
}

// View-DPS - speedometer/gauge
function genIconViewDps() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        const cx = 7.5, cy = 8;
        // Half-circle arc (gauge)
        for (let angle = 180; angle <= 360; angle += 3) {
            const rad = angle * Math.PI / 180;
            const x = Math.round(cx + 6.5 * Math.cos(rad));
            const y = Math.round(cy + 6.5 * Math.sin(rad));
            set(x, y, C[0], C[1], C[2], 210);
        }
        // Needle pointing upper-right
        drawLine(7, 8, 12, 3, set, CW[0], CW[1], CW[2], 255);
        // Tick marks
        for (let angle = 200; angle <= 340; angle += 35) {
            const rad = angle * Math.PI / 180;
            set(Math.round(cx + 6*Math.cos(rad)), Math.round(cy + 6*Math.sin(rad)), C[0], C[1], C[2], 180);
        }
        // Base
        fillRect(1, 12, 14, 13, set, C[0]*0.4, C[1]*0.4, C[2]*0.4, 160);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-view-dps.tga'), s, s, px);
}

// View-HPS - pulse/heartbeat line
function genIconViewHps() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Flat line with pulse in the middle
        const pts = [[0,8],[4,8],[5,5],[7,1],[8,12],[9,4],[11,8],[15,8]];
        for (let i = 0; i < pts.length - 1; i++) {
            drawLine(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1], set, 80, 220, 100, 240);
        }
        // Brighter peak
        set(7, 1, 120, 255, 140, 255);
        set(7, 2, 100, 240, 120, 240);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-view-hps.tga'), s, s, px);
}

// Segment-Current - play triangle
function genIconSegmentCurrent() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Play triangle
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
            const cy = 7.5;
            const maxX = 3 + (1 - Math.abs(y - cy) / cy) * 10;
            if (x >= 3 && x <= maxX && Math.abs(y - cy) < cy) {
                const t = (x - 3) / 10;
                set(x, y, C[0]+(CW[0]-C[0])*t, C[1]+(CW[1]-C[1])*t, C[2]+(CW[2]-C[2])*t, 220);
            }
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-segment-current.tga'), s, s, px);
}

// Segment-Overall - stacked horizontal bars
function genIconSegmentOverall() {
    const s = 16;
    const px = renderIcon(s, s, (w, h, set) => {
        // Three horizontal bars of decreasing width
        fillRect(2, 1, 13, 4, set, CW[0], CW[1], CW[2], 240);
        fillRect(2, 6, 11, 9, set, C[0], C[1], C[2], 210);
        fillRect(2, 11, 7, 14, set, C[0]*0.7, C[1]*0.7, C[2]*0.7, 180);
    });
    writeTGA(path.join(TEXTURES_DIR, 'icon-segment-overall.tga'), s, s, px);
}

// =====================================================================
// BAR TEXTURES (128x16)
// =====================================================================

// Solid bar
function genBarSolid() {
    const W = 128, H = 16;
    const px = renderIcon(W, H, (w, h, set) => {
        for (let y = 0; y < h; y++)
            for (let x = 0; x < w; x++)
                set(x, y, 255, 255, 255, 255);
    });
    writeTGA(path.join(TEXTURES_DIR, 'bar-solid.tga'), W, H, px);
}

// Gradient bar (left bright to right slightly darker)
function genBarGradient() {
    const W = 128, H = 16;
    const px = renderIcon(W, H, (w, h, set) => {
        for (let y = 0; y < h; y++) {
            // Subtle vertical gradient: slightly brighter at top
            const vt = 1 - (y / (h - 1)) * 0.25;
            for (let x = 0; x < w; x++) {
                const v = Math.round(255 * vt);
                set(x, y, v, v, v, 255);
            }
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'bar-gradient.tga'), W, H, px);
}

// Striped bar (diagonal stripes)
function genBarStriped() {
    const W = 128, H = 16;
    const px = renderIcon(W, H, (w, h, set) => {
        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) {
                const stripe = Math.floor((x + y) / 4) % 2;
                const v = stripe ? 255 : 200;
                set(x, y, v, v, v, 255);
            }
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'bar-striped.tga'), W, H, px);
}

// Glossy bar (bright top half, darker bottom half)
function genBarGlossy() {
    const W = 128, H = 16;
    const px = renderIcon(W, H, (w, h, set) => {
        for (let y = 0; y < h; y++) {
            let v;
            if (y < h / 2) {
                // Top half: bright with slight gradient
                v = 255 - Math.round((y / (h/2)) * 30);
            } else {
                // Bottom half: darker
                const t = (y - h/2) / (h/2);
                v = Math.round(180 + t * 40);
            }
            for (let x = 0; x < w; x++) set(x, y, v, v, v, 255);
        }
    });
    writeTGA(path.join(TEXTURES_DIR, 'bar-glossy.tga'), W, H, px);
}

// =====================================================================
// MAIN
// =====================================================================
if (!fs.existsSync(TEXTURES_DIR)) {
    fs.mkdirSync(TEXTURES_DIR, { recursive: true });
}

console.log('Generating Parsec textures...');
console.log('--- Core ---');
generateIcon();
generateBanner();

console.log('--- Settings Icons (16x16) ---');
genIconEye();
genIconEyeClosed();
genIconLock();
genIconMinimap();
genIconMerge();
genIconGroup();
genIconPalette();
genIconBackdrop();

console.log('--- Sidebar Icons (16x16) ---');
genIconGeneral();
genIconWindows();
genIconAutomation();
genIconAbout();

console.log('--- Title Bar Icons (16x16) ---');
genIconSettings();
genIconReset();
genIconAnnounce();
genIconViewDamage();
genIconViewHealing();
genIconViewDps();
genIconViewHps();
genIconSegmentCurrent();
genIconSegmentOverall();

console.log('--- Bar Textures (128x16) ---');
genBarSolid();
genBarGradient();
genBarStriped();
genBarGlossy();

console.log(`\nDone! ${2 + 8 + 4 + 9 + 4} textures generated.`);
