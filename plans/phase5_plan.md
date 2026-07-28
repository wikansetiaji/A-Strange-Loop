# Phase 5: Visual Redesign — "The Strange Loop Library"

## Overview

Complete visual transformation from generic Material 3 (purple seed, soft rounded corners) to a sharp, bold, editorial-terminal aesthetic with rich custom animations and a cohesive design system.

**Direction**: Sharp B&W base with bold accent pops — like an arts zine meets a terminal. Zero border radius, thick structural borders, all-caps labels, dense typography.

---

## Design System

### Colors

| Role | Light | Dark | Hex |
|---|---|---|---|
| Primary (red pen) | `#FF2D55` | `#FF6B81` | Accent bars, buttons, links |
| Secondary (highlighter) | `#FFD60A` | `#FFE045` | Subtle highlights, accent detail |
| Tertiary (fountain pen) | `#5856D6` | `#7B79FF` | Reading Brain button, tertiary elements |
| Surface | `#FAFAFA` | `#0D0D0D` | Main background |
| OnSurface | `#111111` | `#EEEEEE` | Text |
| Outline | `#BBBBBB` | `#555555` | Borders, dividers |
| Error | `#CC0000` | `#FF6B6B` | Error states |

### Typography

| Role | Font | Weight |
|---|---|---|
| Display / Headings | **Syne** | 700–800 |
| Body / Chat / Labels | **Space Grotesk** | 400–600 |

- Via `google_fonts` package (CDN-loaded, works on web)
- App title uses Syne with all-caps + wide letter spacing for magazine-masthead energy

### Visual Language

- **Zero border radius** — every container, button, dialog, and input uses `BorderRadius.zero`
- **Structural borders** — thin 1–1.5px lines separate all major regions (header/body, sidebar/chat, input/messages)
- **All-caps labels** — buttons and section headers use uppercase with tight letter spacing
- **Sharp icons** — all Material Icons replaced with `_sharp` or `_outlined` variants
- **No decorative ornament** — no soft shadows, no gradients, no blur effects

---

## New Files

### `lib/theme/app_theme.dart`

- `AppTheme.light()` / `AppTheme.dark()` — complete `ThemeData` with custom `ColorScheme`, `TextTheme`, component themes
- `AppTextStyles` — static helper class for consistent typography access across the app

### `lib/widgets/animations.dart`

Eight custom animated widgets:

| Widget | Purpose |
|---|---|
| `PulsingLoop` | Lemniscate (∞) path with monochrome sweep gradient, pulsing stroke, and a trailing glowing dot. Used as app logo in header and empty state. |
| `TypingBubble` | Three dots with staggered bounce animation and color-cycling alpha. Replaces static "Thinking..." text. |
| `FloatingDust` | Ambient golden particles drifting slowly. Wraps chat area and login screen for atmosphere. |
| `AnimatedMessageEntrance` | Messages slide up with spring-back + fade-in on first render. Not currently active (removed for terminal feel). |
| `StaggeredEntrance` | Sidebar session tiles appear in staggered sequence. Active in sidebar. |
| `MorphingSendButton` | Send button morphs between arrow icon and BlockLoader, with border state transitions. |
| `BlockLoader` | Blinking block cursor — terminal-style loading indicator. Replaces all `CircularProgressIndicator` instances. |
| `BrainGlow` | Subtle teal pulse glow when brain mutations are active. Available but not currently wired. |

### `lib/theme/` (directory)

Created for design token organization.

---

## Modified Files

### `lib/main.dart`

- Wired in `AppTheme.light()` / `AppTheme.dark()` instead of `ColorScheme.fromSeed`
- Auth loading state uses `BlockLoader` instead of `CircularProgressIndicator`

### `lib/screens/login_screen.dart`

- Bordered container framing the logo + title + subtitle
- `PulsingLoop` replaces static sparkle icon
- "A STRANGE LOOP" title stacked in two lines, all-caps Syne
- Red horizontal rule as visual separator
- "SIGN IN WITH GOOGLE" sharp outlined button with arrow icon
- Error state: bordered box with `error_outline_sharp` icon
- `FloatingDust` particles wrapper for ambient atmosphere
- Fade-in entrance animation on page load

### `lib/screens/chat_screen.dart`

- **Header**: Custom AppBar with zero elevation, `PulsingLoop` logo + "A STRANGE LOOP" title, current reading info separated by vertical rule, sharp icons, bottom border line
- **Empty state**: `PulsingLoop` logo + red horizontal rule + intro text
- **User messages**: Right-aligned bordered boxes (no fill, just stroke)
- **AI messages**: Red left accent bar (3px) with tight 12px spacing to text, subtle `surfaceContainerHighest` background tint at low alpha
- **Input bar**: Bordered container with "Ask me anything, friend..." hint, `MorphingSendButton`
- **Token footer**: Centered small text showing message count + token usage
- **Error banner**: `MaterialBanner` with error styling
- `FloatingDust` particles wrapper (12 particles)
- `TypingBubble` during streaming wait

### `lib/widgets/sidebar.dart`

- **Branding removed** — no longer shows app name or logo (moved to header)
- Starts directly with "NEW CHAT" filled button (red, sharp)
- "READING BRAIN" button: sharp bordered box with `psychology_outlined` icon
- Search field: sharp bordered container with `search_sharp` / `close_sharp` icons
- Section headers: small red dash prefix + all-caps label
- Session tiles: `StaggeredEntrance` animation on load
- Empty/search states: sharp outlined icons
- Delete dialog: sharp, zero-radius

### `lib/widgets/session_tile.dart`

- Active state: red vertical accent bar (3px) on the left edge
- Bold title for active, regular for inactive
- Sharp icon variants for pin/delete

### `pubspec.yaml`

- Added `google_fonts: ^6.0.0` dependency

---

## Design Iterations

### Round 1: Warm library + strange loop
- Purple + amber, Cormorant Garamond + DM Sans, soft corners, rounded everything
- **User feedback**: Didn't like colors or fonts

### Round 2: Sharp & bold editorial
- B&W + red/yellow/purple accents, Syne + Space Grotesk, zero radius
- **User feedback**: Liked it. "Almost terminal like."

### Round 3: Refinements
- Navbar redesigned to show on all screen sizes (was hidden on wide)
- Reading Brain button restyled to match sharp aesthetic
- `BlockLoader` created to replace basic `CircularProgressIndicator`
- All icons switched to `_sharp` / `_outlined` variants
- Sidebar branding removed, logo + title moved to navbar header
- PulsingLoop colors changed from red+yellow gradient to monochrome
- AI reply bubble spacing tightened (red bar now 12px from text)

### Round 4: Terminal overreach (reverted)
- Brief experiment with `> ` prompt prefix, `surfaceContainerLow` chat background, no animations, stripped everything
- **User feedback**: Preferred previous version. Reverted most changes, kept only tighter AI spacing.

---

## Key Design Decisions

1. **Monochrome PulsingLoop** — Single-color sweep gradient (alpha-varying) instead of red+yellow multi-color. Cohesive with B&W aesthetic.

2. **Red accent bar on AI messages** — The 3px red left border is the strongest visual signature. It signals "assistant speaking" without cluttering. Spacing tuned to 12px for breathing room.

3. **No border radius anywhere** — Deliberate constraint. Even the login screen box, buttons, dialogs, and input fields are all sharp rectangles. This is the core of the "terminal" feel.

4. **All-caps Syne for branding** — The app name "A STRANGE LOOP" uses Syne at weight 800 with 1.2px letter spacing. Magazine-masthead energy that sets the tone.

5. **FloatingDust as ambient layer** — The only "soft" element in the design. Subtle golden particles drifting in the background keep the experience from feeling cold.

---

## Not in Scope (Future)

- Dark mode refinements (functional but not optimized)
- Brain mutation glow animation wiring
- Custom transition animations (page turn, etc.)
- Custom icon set (currently using Material sharp variants)
- Font size / spacing responsiveness for very small screens
