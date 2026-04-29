# Design System Strategy: The Neon Sovereign

## 1. Overview & Creative North Star

This design system is built upon the **"The Digital Curator"** Creative North Star. It rejects the utility-first aesthetic of standard fintech for an editorial, high-stakes marketplace feel. The objective is to make digital asset acquisition feel like a premium ritual, not a chore.

We break the "template" look through **intentional depth layering** and **asymmetric focal points**. By utilizing wide rounded corners (`xl: 3rem`) and floating glass surfaces, the UI feels less like a flat screen and more like a physical, illuminated console. The contrast between the deep `background: #0d0d19` and the electric `primary: #c59aff` creates a high-energy, gaming-adjacent atmosphere that commands attention and conveys high value.

---

## 2. Colors & Surface Philosophy

The color palette is a sophisticated interplay between "infinite depth" and "neon precision."

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders to section off content. Boundaries must be defined solely through background color shifts.
- Use `surface-container-low` to define a section against the `surface` background.
- Use spacing (e.g., `8: 2rem`) to create natural visual breaks.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers.
*   **Base:** `surface-dim (#0d0d19)` - The infinite canvas.
*   **Secondary Sections:** `surface-container (#181827)` - For grouping related items.
*   **Active/Hero Cards:** `surface-container-highest (#242436)` - Use this for the "Most Popular" or "Selected" states to create a physical "lift."

### The "Glass & Gradient" Rule
Floating elements (like purchase confirmations or floating labels) must use **Glassmorphism**:
- **Background:** `surface-variant (#242436)` at 60% opacity.
- **Backdrop Blur:** 20px - 40px.
- **Edge Highlight:** A "Ghost Border" (see Section 4) to catch the light.

### Signature Textures
Main CTAs and high-value banners should never be flat. Apply a linear gradient from `primary_dim (#9547f7)` to `primary (#c59aff)` at a 135-degree angle to provide "visual soul." For "Best Value" highlights, use the `secondary (#ffd709)` to `secondary_fixed_dim (#efc900)` gradient.

---

## 3. Typography: Editorial Authority

We use a tri-font system to create a sophisticated hierarchy that feels both modern and technical.

*   **Display & Headlines (Plus Jakarta Sans):** Used for large price points and page titles. The wide aperture of this font communicates openness and modernity. Use `display-md` for coin amounts to make them the undeniable hero.
*   **Titles & Body (Manrope):** The workhorse. Manrope's geometric nature provides a clean, neutral balance to the aggressive display styles. Use `title-lg` for "Standard Pack" labels.
*   **Labels (Space Grotesk):** This technical, monospaced-leaning font is reserved for "Bonus" percentages and metadata. It adds a layer of "gaming/hacker" sophistication.

---

## 4. Elevation & Depth

Hierarchy is achieved through **Tonal Layering**, mimicking how light interacts with dark surfaces.

*   **The Layering Principle:** Place a `surface-container-highest` card inside a `surface-container-low` area to create a soft, natural lift. Avoid drop shadows on nested items.
*   **Ambient Shadows:** For floating action buttons or high-priority purchase cards, use a diffused shadow:
    *   **Color:** `#000000` at 40% opacity OR a tinted `primary` shadow at 10% opacity for a "glow" effect.
    *   **Blur:** `32px` to `64px`.
*   **The "Ghost Border":** When accessibility requires a container edge, use the `outline-variant (#474755)` at 20% opacity. This creates a "subtle refraction" effect rather than a hard line.
*   **Glow States:** Active selections should emit a subtle outer glow using `primary_dim` with a 20px spread and 15% opacity, simulating an LED backlit surface.

---

## 5. Components

### Buttons
*   **Primary (The High-Value CTA):** Gradient fill (`primary_dim` to `primary`). `xl` rounded corners. Typography: `title-sm` (Manrope Bold).
*   **Secondary:** Glassmorphism style. `surface-variant` at 20% opacity with a `Ghost Border`.

### Purchase Cards
*   **Layout:** No dividers. Use `surface-container-high` as the card base. 
*   **Focus:** Use an asymmetric layout where the coin icon and amount are on the left, and the price is anchored to the right in `display-sm`.
*   **Badges:** "Most Popular" badges should "break" the top border of the card, using a `secondary` (Gold) gradient to denote luxury.

### Input Fields
*   **Style:** Minimalist. No bottom line or box. Use `surface-container-low` with a subtle `outline-variant` Ghost Border.
*   **Active State:** The border transitions to a 100% opaque `primary` (Electric Violet) Glow.

### Coins & Icons
*   **Iconography:** Icons should be multi-tonal. Use `secondary` (Gold) for the icon body with a `secondary_container` inner shadow to give the coins "weight."

---

## 6. Do's and Don'ts

### Do:
*   **Do** use extreme white space (`spacing-12` or `spacing-16`) between major functional groups to let the "Digital Curator" aesthetic breathe.
*   **Do** use color to denote value: `tertiary (#ff6b9b)` for limited-time offers and `secondary` (Gold) for permanent high-value packs.
*   **Do** ensure that the `on_surface` text color stays at high contrast against the dark background for accessibility.

### Don't:
*   **Don't** use 1px solid separators. It shatters the high-end glass illusion.
*   **Don't** use pure white (`#ffffff`). Use `on_background (#e6e3f5)` for text to avoid "harsh" ocular strain in dark mode.
*   **Don't** use small corner radii. Any radius below `1rem` (DEFAULT) will make the system feel dated and "boxy."