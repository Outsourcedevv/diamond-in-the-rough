// Draws the game pass pictures for the themes and the haystack skin sold in
// the sidebar's Themes card (see src/shared/ThemeShop.luau): one 512 x 512
// PNG per pass, ready to upload in the Creator Dashboard (the game, then
// Monetization, then Passes). Roblox shows pass pictures as circles, so
// everything that matters sits inside the middle circle.
//
//     node art/gamepasses/make.mjs [path/to/chrome]
//
// Writes <key>.svg and <key>.png next to this file.
import { execFileSync } from "node:child_process";
import { writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
// Chrome's headless shell, whose page is exactly the window's size.
const chrome = process.argv[2] || "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell";
const SIZE = 512;

// The same pictures every time.
let seed = 7;
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const between = (a, b) => a + random() * (b - a);
const pick = (list) => list[Math.floor(random() * list.length)];

const glow = (id, blur) => `<filter id="${id}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${blur}"/></filter>`;
const skyGradient = (id, top, bottom) => `<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${top}"/><stop offset="1" stop-color="${bottom}"/></linearGradient>`;

// The name on a ribbon at the bottom, with what it is (a theme or a skin) above.
function ribbon(name, tag) {
	const tagWidth = tag.length * 9.5 + 34;
	return `
	<g font-family="DejaVu Sans, Liberation Sans, sans-serif" font-weight="bold" text-anchor="middle">
		<rect x="98" y="390" width="316" height="62" rx="31" fill="#141c48" fill-opacity="0.92" stroke="#f6c85c" stroke-width="4"/>
		<text x="256" y="432" font-size="${name.length > 9 ? 27 : 31}" fill="#ffffff" letter-spacing="1.5">${name}</text>
		<rect x="${256 - tagWidth / 2}" y="370" width="${tagWidth}" height="26" rx="13" fill="#f6c85c"/>
		<text x="256" y="388.5" font-size="13" fill="#141c48" letter-spacing="1.5">${tag}</text>
	</g>`;
}


function svg(defs, body, name, tag) {
	return `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 512 512">
	<defs>${defs}</defs>
	${body}
	${ribbon(name, tag)}
</svg>`;
}

// ---------------------------------------------------------------- Sakura
function blossoms(points, count, colours) {
	let out = "";
	for (const [x, y, spread] of points) {
		for (let i = 0; i < count; i++) {
			const r = between(7, 15);
			out += `<circle cx="${(x + between(-spread, spread)).toFixed(1)}" cy="${(y + between(-spread * 0.7, spread * 0.7)).toFixed(1)}" r="${r.toFixed(1)}" fill="${pick(colours)}"/>`;
		}
	}
	return out;
}
function flower(x, y, r) {
	let petals = "";
	for (let k = 0; k < 5; k++) {
		const a = (k * 72 * Math.PI) / 180;
		petals += `<ellipse cx="${(x + Math.sin(a) * r * 0.55).toFixed(1)}" cy="${(y - Math.cos(a) * r * 0.55).toFixed(1)}" rx="${(r * 0.42).toFixed(1)}" ry="${(r * 0.58).toFixed(1)}" transform="rotate(${k * 72} ${(x + Math.sin(a) * r * 0.55).toFixed(1)} ${(y - Math.cos(a) * r * 0.55).toFixed(1)})" fill="#ffe3ec"/>`;
	}
	return petals + `<circle cx="${x}" cy="${y}" r="${(r * 0.22).toFixed(1)}" fill="#ff6f9c"/>`;
}
function sakura() {
	const pinks = ["#ffb3cb", "#ff97b8", "#ffc9da", "#ffa6c4", "#ffd7e4"];
	let petals = "";
	for (let i = 0; i < 26; i++) {
		const x = between(20, 492), y = between(40, 380);
		petals += `<ellipse cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" rx="6" ry="3.4" transform="rotate(${between(0, 180).toFixed(0)} ${x.toFixed(1)} ${y.toFixed(1)})" fill="${pick(pinks)}" opacity="0.9"/>`;
	}
	const defs = skyGradient("sky", "#ffe9f0", "#f6a9c2") + glow("soft", 8) +
		`<linearGradient id="hill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8cc063"/><stop offset="1" stop-color="#5e9443"/></linearGradient>`;
	const body = `
	<rect width="512" height="512" fill="url(#sky)"/>
	<circle cx="256" cy="200" r="78" fill="#fff6f2" opacity="0.9" filter="url(#soft)"/>
	<path d="M10 340 L175 158 L222 196 L282 132 L500 340 Z" fill="#c7a1cf"/>
	<path d="M175 158 L146 190 L162 186 L176 200 L196 184 L222 196 Z M282 132 L246 172 L266 166 L282 182 L300 166 L322 176 Z" fill="#fbf4ff"/>
	<path d="M0 330 Q130 296 256 322 T512 312 V512 H0 Z" fill="url(#hill)"/>
	<path d="M0 372 Q160 340 300 368 T512 360 V512 H0 Z" fill="#558a3c"/>
	<g>
		<rect x="208" y="252" width="15" height="104" fill="#d8302a"/>
		<rect x="289" y="252" width="15" height="104" fill="#d8302a"/>
		<rect x="190" y="272" width="132" height="11" fill="#d8302a"/>
		<rect x="250" y="250" width="12" height="24" fill="#d8302a"/>
		<path d="M172 238 Q256 226 340 238 L344 252 Q256 242 168 252 Z" fill="#2a2124"/>
		<path d="M180 250 L332 250 L330 258 L182 258 Z" fill="#d8302a"/>
	</g>
	<path d="M-12 118 Q70 112 140 76 Q186 54 238 62" stroke="#5b3a32" stroke-width="15" fill="none" stroke-linecap="round"/>
	<path d="M90 100 Q110 140 96 176" stroke="#5b3a32" stroke-width="8" fill="none" stroke-linecap="round"/>
	<path d="M524 176 Q450 164 404 120 Q376 94 330 92" stroke="#5b3a32" stroke-width="14" fill="none" stroke-linecap="round"/>
	<path d="M440 150 Q430 196 450 226" stroke="#5b3a32" stroke-width="8" fill="none" stroke-linecap="round"/>
	${blossoms([[20, 108, 34], [86, 96, 34], [150, 70, 32], [214, 58, 30], [98, 170, 24]], 16, pinks)}
	${blossoms([[500, 170, 34], [430, 140, 34], [370, 100, 30], [334, 90, 24], [450, 222, 24]], 16, pinks)}
	${flower(60, 96, 15)}${flower(176, 64, 13)}${flower(122, 112, 12)}${flower(462, 150, 15)}${flower(392, 108, 13)}${flower(452, 214, 12)}
	${petals}`;
	return svg(defs, body, "SAKURA", "MAP THEME");
}

// ---------------------------------------------------------------- Farm
function cow(x, y) {
	return `<g>
		<rect x="${x - 34}" y="${y + 14}" width="9" height="30" rx="3" fill="#f4efe6"/><rect x="${x - 18}" y="${y + 16}" width="9" height="30" rx="3" fill="#e5ddd0"/>
		<rect x="${x + 18}" y="${y + 14}" width="9" height="30" rx="3" fill="#f4efe6"/><rect x="${x + 32}" y="${y + 16}" width="9" height="30" rx="3" fill="#e5ddd0"/>
		<ellipse cx="${x}" cy="${y}" rx="48" ry="28" fill="#f8f4ee"/>
		<path d="M${x - 20} ${y - 26} q14 8 6 22 q-14 6 -22 -6 q-2 -12 16 -16 Z" fill="#26211f"/>
		<ellipse cx="${x + 20}" cy="${y + 6}" rx="13" ry="10" fill="#26211f"/>
		<ellipse cx="${x + 4}" cy="${y + 20}" rx="9" ry="5" fill="#26211f"/>
		<path d="M${x + 46} ${y - 6} q12 18 4 30" stroke="#f8f4ee" stroke-width="4" fill="none" stroke-linecap="round"/>
		<rect x="${x - 72}" y="${y - 30}" width="34" height="38" rx="12" fill="#f8f4ee"/>
		<ellipse cx="${x - 62}" cy="${y + 2}" rx="16" ry="11" fill="#f2a7a7"/>
		<circle cx="${x - 67}" cy="${y + 2}" r="2.4" fill="#7a3d3d"/><circle cx="${x - 57}" cy="${y + 2}" r="2.4" fill="#7a3d3d"/>
		<circle cx="${x - 62}" cy="${y - 16}" r="3.4" fill="#26211f"/>
		<path d="M${x - 70} ${y - 30} q-6 -12 2 -14 M${x - 44} ${y - 30} q6 -12 -2 -14" stroke="#efe2c4" stroke-width="5" fill="none" stroke-linecap="round"/>
		<ellipse cx="${x - 40}" cy="${y - 24}" rx="9" ry="5" fill="#26211f" transform="rotate(25 ${x - 40} ${y - 24})"/>
	</g>`;
}
function farm() {
	let rows = "";
	for (let i = 0; i < 9; i++) rows += `<path d="M${-40 + i * 70} 512 Q${150 + i * 30} 380 ${200 + i * 26} 344" stroke="#c3a04a" stroke-width="5" fill="none" opacity="0.55"/>`;
	let fence = "";
	for (let x = 14; x < 512; x += 44) fence += `<rect x="${x}" y="350" width="9" height="40" rx="2" fill="#f2e6cc"/>`;
	const defs = skyGradient("sky", "#fff0c4", "#f7bb6c") + glow("soft", 10) +
		`<linearGradient id="barn" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#c8302e"/><stop offset="1" stop-color="#a32325"/></linearGradient>` +
		`<linearGradient id="silo" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#dcd7ce"/><stop offset="1" stop-color="#a9a399"/></linearGradient>`;
	const body = `
	<rect width="512" height="512" fill="url(#sky)"/>
	<circle cx="396" cy="118" r="70" fill="#fff4c8" opacity="0.8" filter="url(#soft)"/>
	<circle cx="396" cy="118" r="42" fill="#fff6d6"/>
	<ellipse cx="110" cy="110" rx="58" ry="18" fill="#fffaf0" opacity="0.85"/><ellipse cx="140" cy="96" rx="34" ry="18" fill="#fffaf0" opacity="0.85"/>
	<path d="M0 300 Q120 246 250 290 T512 270 V512 H0 Z" fill="#a9c26a"/>
	<path d="M0 340 Q256 300 512 336 V512 H0 Z" fill="#d6b65a"/>
	${rows}
	<rect x="350" y="168" width="54" height="182" fill="url(#silo)"/>
	<path d="M350 170 Q377 128 404 170 Z" fill="#7d8794"/>
	<path d="M350 206 H404 M350 246 H404 M350 286 H404 M350 326 H404" stroke="#8f897f" stroke-width="3"/>
	<rect x="150" y="222" width="190" height="130" fill="url(#barn)"/>
	<path d="M138 228 L166 176 L245 148 L324 176 L352 228 Z" fill="#7c1b1d"/>
	<path d="M138 228 L166 176 L245 148 L324 176 L352 228" stroke="#fbf4e8" stroke-width="7" fill="none" stroke-linejoin="round"/>
	<rect x="225" y="186" width="40" height="32" fill="#fbf4e8"/><rect x="231" y="192" width="28" height="20" fill="#3a1414"/>
	<rect x="203" y="276" width="84" height="76" fill="#fbf4e8"/><rect x="209" y="282" width="72" height="70" fill="#b42a2a"/>
	<path d="M209 282 L281 352 M281 282 L209 352" stroke="#fbf4e8" stroke-width="6"/>
	<rect x="160" y="250" width="26" height="22" fill="#fbf4e8"/><rect x="304" y="250" width="26" height="22" fill="#fbf4e8"/>
	${fence}
	<rect x="0" y="358" width="512" height="8" fill="#f2e6cc"/><rect x="0" y="376" width="512" height="8" fill="#f2e6cc"/>
	${cow(124, 330)}`;
	return svg(defs, body, "FARM", "MAP THEME");
}

// ---------------------------------------------------------------- Desert
function palm(x, y, height, lean, scale) {
	const topX = x + lean, topY = y - height;
	let fronds = "";
	for (const angle of [-175, -150, -125, -100, -75, -50, -25, 0, 25, 195]) {
		const a = (angle * Math.PI) / 180;
		const ex = topX + Math.cos(a) * 62 * scale, ey = topY + Math.sin(a) * 62 * scale + 26 * scale;
		const cx = topX + Math.cos(a) * 34 * scale, cy = topY + Math.sin(a) * 40 * scale - 14 * scale;
		fronds += `<path d="M${topX} ${topY} Q${cx.toFixed(1)} ${cy.toFixed(1)} ${ex.toFixed(1)} ${ey.toFixed(1)} Q${(cx + 6).toFixed(1)} ${(cy + 14).toFixed(1)} ${topX} ${topY} Z" fill="${pick(["#2f8a3c", "#3fa04a", "#27773a"])}"/>`;
	}
	return `<path d="M${x} ${y} Q${x + lean * 0.2} ${y - height * 0.6} ${topX} ${topY}" stroke="#8a5a32" stroke-width="${10 * scale}" fill="none" stroke-linecap="round"/>
		<path d="M${x} ${y} Q${x + lean * 0.2} ${y - height * 0.6} ${topX} ${topY}" stroke="#6e4426" stroke-width="${10 * scale}" stroke-dasharray="3 9" fill="none"/>
		${fronds}<circle cx="${topX}" cy="${topY + 4}" r="${5 * scale}" fill="#5a3a20"/>`;
}
function desert() {
	const defs = skyGradient("sky", "#ffe3a8", "#f4925a") + glow("soft", 12) +
		`<linearGradient id="mesa" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c6643a"/><stop offset="1" stop-color="#9a4329"/></linearGradient>` +
		`<linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6ee0dc"/><stop offset="1" stop-color="#2aa8b4"/></linearGradient>`;
	const strata = (x1, x2, ys) => ys.map((y) => `<path d="M${x1} ${y} H${x2}" stroke="#a54b2d" stroke-width="3" opacity="0.7"/>`).join("");
	const body = `
	<rect width="512" height="512" fill="url(#sky)"/>
	<circle cx="256" cy="180" r="96" fill="#ffdb7a" opacity="0.7" filter="url(#soft)"/>
	<circle cx="256" cy="180" r="62" fill="#ffe08a"/>
	<path d="M120 300 L150 236 L230 232 L250 300 Z M300 300 L318 226 L368 222 L390 300 Z" fill="#dc9363"/>
	<path d="M0 312 V186 L24 176 L118 176 L134 198 L150 312 Z" fill="url(#mesa)"/>
	${strata(4, 132, [206, 232, 262])}
	<path d="M372 312 L390 158 L470 152 L512 162 V312 Z" fill="url(#mesa)"/>
	${strata(388, 512, [190, 224, 260])}
	<path d="M0 318 Q150 280 300 312 T512 300 V512 H0 Z" fill="#eab575"/>
	<path d="M0 382 Q200 340 512 376 V512 H0 Z" fill="#d89a5c"/>
	<ellipse cx="256" cy="348" rx="128" ry="26" fill="#6aa84f"/>
	<ellipse cx="256" cy="348" rx="112" ry="19" fill="url(#water)"/>
	<path d="M190 344 Q256 338 322 344" stroke="#d6fbf8" stroke-width="3" fill="none" opacity="0.8"/>
	${palm(318, 346, 116, 28, 1)}
	${palm(196, 348, 84, -22, 0.78)}
	<g fill="#4f8f3e"><rect x="430" y="300" width="16" height="74" rx="8"/><path d="M432 336 h-14 a7 7 0 0 1 -7 -7 v-18 a6 6 0 0 1 12 0 v12 h9 Z"/><path d="M444 322 h13 a6 6 0 0 0 6 -6 v-16 a6 6 0 0 0 -12 0 v10 h-7 Z"/></g>`;
	return svg(defs, body, "DESERT", "MAP THEME");
}

// ---------------------------------------------------------------- Haunted
function bat(x, y, s) {
	return `<path transform="translate(${x} ${y}) scale(${s})" d="M0 0 Q-8 -10 -20 -6 Q-14 -2 -16 4 Q-10 0 -6 4 Q-3 0 0 4 Q3 0 6 4 Q10 0 16 4 Q14 -2 20 -6 Q8 -10 0 0 Z" fill="#0b0d18"/>`;
}
function haunted() {
	let stars = "";
	for (let i = 0; i < 40; i++) stars += `<circle cx="${between(10, 502).toFixed(0)}" cy="${between(10, 230).toFixed(0)}" r="${between(0.8, 2).toFixed(1)}" fill="#fff" opacity="${between(0.4, 0.9).toFixed(2)}"/>`;
	const lantern = (x, y) => `<line x1="${x}" y1="${y - 64}" x2="${x}" y2="${y + 70}" stroke="#151821" stroke-width="5"/>
		<path d="M${x} ${y - 64} h22 v10" stroke="#151821" stroke-width="4" fill="none"/>
		<circle cx="${x + 22}" cy="${y - 34}" r="30" fill="#ffb046" opacity="0.55" filter="url(#glow)"/>
		<rect x="${x + 10}" y="${y - 52}" width="24" height="30" rx="6" fill="#ffc35c" stroke="#3a2a14" stroke-width="3"/>
		<rect x="${x + 14}" y="${y - 58}" width="16" height="7" rx="2" fill="#3a2a14"/>`;
	const defs = skyGradient("sky", "#2c3576", "#0f1330") + glow("glow", 9) + glow("fog", 14) + glow("moonglow", 22);
	const window = (x, y, w, h) => `<rect x="${x - 4}" y="${y - 4}" width="${w + 8}" height="${h + 8}" fill="#ffb046" opacity="0.6" filter="url(#glow)"/><rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#ffc35c"/>`;
	const body = `
	<rect width="512" height="512" fill="url(#sky)"/>
	${stars}
	<circle cx="318" cy="150" r="104" fill="#f4ecc8" opacity="0.35" filter="url(#moonglow)"/>
	<circle cx="318" cy="150" r="76" fill="#f6efd0"/>
	<circle cx="292" cy="128" r="14" fill="#e3d9b0"/><circle cx="340" cy="172" r="18" fill="#e3d9b0"/><circle cx="346" cy="122" r="8" fill="#e3d9b0"/>
	${bat(150, 96, 1.4)}${bat(204, 140, 1)}${bat(420, 70, 1.1)}
	<path d="M0 330 Q120 262 256 280 T512 300 V512 H0 Z" fill="#1c2430"/>
	<g fill="#121620">
		<path d="M190 286 V214 L232 176 L274 214 V286 Z"/>
		<path d="M262 286 V196 H316 V286 Z"/>
		<path d="M256 200 L289 128 L322 200 Z"/>
		<path d="M176 220 L232 166 L288 220 Z"/>
		<rect x="300" y="150" width="7" height="30"/>
	</g>
	${window(220, 222, 22, 26)}${window(278, 214, 20, 24)}${window(282, 252, 20, 22)}${window(198, 252, 18, 20)}
	<path d="M60 340 Q66 260 52 200 M58 270 Q30 240 12 236 M56 236 Q84 206 108 204 M54 210 Q40 178 46 150 M92 206 Q106 186 104 168" stroke="#0d1017" stroke-width="9" fill="none" stroke-linecap="round"/>
	<g fill="#3a4252"><path d="M390 372 v-34 a18 18 0 0 1 36 0 v34 Z"/><path d="M118 380 v-26 a14 14 0 0 1 28 0 v26 Z"/><rect x="452" y="330" width="9" height="44"/><rect x="438" y="344" width="37" height="9"/></g>
	<ellipse cx="160" cy="352" rx="200" ry="26" fill="#cfd8ff" opacity="0.16" filter="url(#fog)"/>
	<ellipse cx="380" cy="336" rx="200" ry="22" fill="#cfd8ff" opacity="0.14" filter="url(#fog)"/>
	<path d="M0 384 Q256 352 512 384 V512 H0 Z" fill="#141a24"/>
	${lantern(150, 320)}${lantern(340, 316)}`;
	return svg(defs, body, "HAUNTED", "MAP THEME");
}

// ---------------------------------------------------------------- Hay & needle
function hay() {
	let straws = "";
	for (let i = 0; i < 230; i++) {
		// Points inside the stack's dome.
		const x = between(104, 408), y = between(168, 370);
		const half = 152 - Math.abs(x - 256) * 0;
		const top = 372 - (372 - 160) * Math.sqrt(Math.max(0, 1 - ((x - 256) / half) ** 2));
		if (y < top + 8) continue;
		const a = between(-40, 40) + (x < 256 ? 10 : -10), len = between(14, 30);
		const r = (a * Math.PI) / 180;
		straws += `<path d="M${x.toFixed(1)} ${y.toFixed(1)} l${(Math.sin(r) * len).toFixed(1)} ${(-Math.cos(r) * len).toFixed(1)}" stroke="${pick(["#c08a2c", "#fbe28c", "#e7b24a", "#b07a22"])}" stroke-width="${between(1.8, 3.2).toFixed(1)}" stroke-linecap="round"/>`;
	}
	let loose = "";
	for (let i = 0; i < 18; i++) {
		const x = between(60, 460), y = between(368, 388), a = between(-80, 80), r = (a * Math.PI) / 180, len = between(14, 26);
		loose += `<path d="M${x.toFixed(1)} ${y.toFixed(1)} l${(Math.sin(r) * len).toFixed(1)} ${(-Math.cos(r) * len * 0.3).toFixed(1)}" stroke="${pick(["#e7b24a", "#fbe28c"])}" stroke-width="2.4" stroke-linecap="round"/>`;
	}
	const sparkle = (x, y, s) => `<path transform="translate(${x} ${y}) scale(${s})" d="M0 -16 Q2 -2 16 0 Q2 2 0 16 Q-2 2 -16 0 Q-2 -2 0 -16 Z" fill="#ffffff"/>`;
	const defs = skyGradient("sky", "#bfe3fb", "#78b2e4") + glow("soft", 10) + glow("shine", 6) +
		`<linearGradient id="stack" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6d977"/><stop offset="0.6" stop-color="#e2ac48"/><stop offset="1" stop-color="#c98e30"/></linearGradient>` +
		`<linearGradient id="steel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#8e99a8"/><stop offset="0.45" stop-color="#ffffff"/><stop offset="1" stop-color="#9aa6b4"/></linearGradient>` +
		`<clipPath id="dome"><path d="M104 372 Q104 168 256 156 Q408 168 408 372 Z"/></clipPath>`;
	// The needle: its eye end sticks up out of the hay, the rest is in the stack,
	// under the straws.
	const needle = `<g transform="rotate(-22 330 210)">
		<path d="M321 70 Q330 58 339 70 L337 250 L330 290 L323 250 Z" fill="url(#steel)" stroke="#6f7b8a" stroke-width="2"/>
		<rect x="327" y="76" width="6" height="26" rx="3" fill="#2e5a8a"/>
	</g>`;
	const thread = `<path d="M286 100 C250 52 196 70 206 112 C214 148 178 170 146 150 C126 138 116 156 124 178" stroke="#d8343a" stroke-width="5" fill="none" stroke-linecap="round"/>
		<path d="M286 100 C306 96 318 78 306 64 C298 56 290 66 298 74" stroke="#d8343a" stroke-width="5" fill="none" stroke-linecap="round"/>`;
	const body = `
	<rect width="512" height="512" fill="url(#sky)"/>
	<circle cx="96" cy="96" r="58" fill="#fff7d0" opacity="0.8" filter="url(#soft)"/>
	<circle cx="96" cy="96" r="36" fill="#fff8da"/>
	<ellipse cx="420" cy="92" rx="52" ry="16" fill="#ffffff" opacity="0.9"/><ellipse cx="444" cy="80" rx="30" ry="16" fill="#ffffff" opacity="0.9"/>
	<path d="M0 342 Q256 312 512 340 V512 H0 Z" fill="#86c25a"/>
	<path d="M0 380 Q256 356 512 384 V512 H0 Z" fill="#6aa846"/>
	<ellipse cx="256" cy="374" rx="170" ry="16" fill="#3f6d2a" opacity="0.45"/>
	<path d="M104 372 Q104 168 256 156 Q408 168 408 372 Z" fill="url(#stack)"/>
	${needle}
	<g clip-path="url(#dome)">${straws}</g>
	<path d="M120 196 q14 -26 30 -12 M196 160 q10 -26 24 -10 M360 190 q16 -22 28 -4 M150 178 q-8 -24 8 -26" stroke="#fbe28c" stroke-width="3" fill="none" stroke-linecap="round"/>
	${loose}
	${thread}
	<circle cx="296" cy="72" r="18" fill="#ffffff" opacity="0.6" filter="url(#shine)"/>
	${sparkle(300, 70, 1.1)}${sparkle(214, 210, 0.6)}${sparkle(372, 150, 0.7)}
	<g><rect x="400" y="320" width="84" height="54" rx="8" fill="#e2ac48"/><path d="M400 336 H484 M400 358 H484" stroke="#b07a22" stroke-width="3"/><path d="M424 320 V374 M458 320 V374" stroke="#8a5a1c" stroke-width="4"/></g>`;
	return svg(defs, body, "HAY &amp; NEEDLE", "MOUNTAIN SKIN");
}

const passes = { sakura, farm, desert, haunted, hay };
const work = mkdtempSync(join(tmpdir(), "gamepasses-"));
try {
	for (const [key, draw] of Object.entries(passes)) {
		const picture = draw();
		writeFileSync(join(here, `${key}.svg`), picture);
		const page = join(work, `${key}.html`);
		writeFileSync(page, `<!doctype html><html><body style="margin:0;background:#000">${picture}</body></html>`);
		execFileSync(chrome, ["--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars", `--window-size=${SIZE},${SIZE}`,
			`--screenshot=${join(here, `${key}.png`)}`, `file://${page}`], { stdio: "ignore" });
		console.log(`${key}.png`);
	}
} finally {
	rmSync(work, { recursive: true, force: true });
}
