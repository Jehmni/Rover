# Design System Document

## 1. Overview & Creative North Star: "The Intelligent Navigator"

The "Intelligent Navigator" is the creative heart of this design system. We are not building just another utility app; we are crafting a high-end editorial experience for community logistics. By merging the functional rigor of **Google Maps**, the typographic clarity of **Notion**, and the frictionless motion of **Uber**, we create an identity that feels **Reliable, Calm, and Intelligent**.

This system moves away from the "boxed-in" feel of traditional apps. We embrace **soft minimalism**, where hierarchy is defined by light, depth, and tonal shifts rather than harsh dividers. The layout is intentional, utilizing asymmetric white space and layered surfaces to guide the eye precisely where it needs to be, reducing the cognitive load for Admins, Drivers, and Attendees alike.

---

## 2. Colors & Surface Philosophy

Our palette is anchored in Teal and Amber, but its premium feel comes from how these tones interact with neutral surfaces.

### Tonal Hierarchy
- **Primary (#006943):** Used for critical actions and brand presence.
- **Secondary (#855300):** Reserved for highlights, active states, and "Amber" alerts.
- **Surface Strategy:** We utilize the Material `surface-container` tokens to create a "nested" world.
    - `surface`: The base canvas.
    - `surface-container-low`: Primary sections or sidebars.
    - `surface-container-lowest`: Interactive cards and floating elements.

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders to section content. Boundaries must be defined solely through background color shifts. For example, a `surface-container-low` section sitting on a `surface` background provides all the separation needed.

### Glass & Gradient Rule
To achieve a "signature" feel, floating UI elements (like the Driver’s ETA card or Map controls) must use **Glassmorphism**. Apply a semi-transparent `surface` color with a `backdrop-filter: blur(20px)`. Main CTAs should utilize a subtle linear gradient from `primary` to `primary_container` to provide a tactile, high-end "soul."

---

## 3. Typography: The Editorial Edge

Using **Inter** as our sole typeface, we achieve intelligence through a vast contrast in scale and weight.

- **Display (Display-LG 3.5rem):** Used sparingly for large, welcoming onboarding states or significant milestones.
- **Headline (Headline-SM 1.5rem):** The workhorse for page titles and major sections. High-utility pages like the "Driver Dashboard" use this for clarity.
- **Body (Body-MD 0.875rem):** The standard for all informational content. It is optimized for legibility during movement (Driver role).
- **Label (Label-SM 0.6875rem):** Used for status chips and metadata. 

**Brand Voice:** Typography is our primary tool for authority. By using wider letter spacing on `Labels` and tight leading on `Headlines`, we mimic the aesthetic of a premium digital journal.

---

## 4. Elevation & Depth: Tonal Layering

Traditional shadows are often "dirty." In this system, depth is achieved through **Tonal Layering**.

- **The Layering Principle:** Instead of a shadow, place a `surface-container-lowest` card on top of a `surface-container-low` background. The shift in tone creates a natural, soft lift.
- **Ambient Shadows:** For elements that must float (e.g., Map Markers), use extra-diffused shadows.
    - *Blur:* 16px–24px.
    - *Opacity:* 4%–6%.
    - *Color:* Use a tinted version of `on-surface` rather than pure black.
- **The "Ghost Border" Fallback:** If accessibility requires a container edge, use a "Ghost Border": the `outline-variant` token at **15% opacity**. Never use 100% opaque borders for cards.

---

## 5. Components

### Buttons & Inputs
- **Primary Button:** Gradient (`primary` to `primary_container`), `xl` (0.75rem) roundedness. No border.
- **Secondary Button:** `surface-container-high` background with `primary` text.
- **Input Fields:** Use `surface-container-highest` for the field background. Labels use `label-md` in `on-surface-variant`. Error states use `error` tokens with a 2px `error` bottom-border only, maintaining the "No-Line" rule elsewhere.

### Status Chips (The Traffic Light System)
Chips use `full` roundedness and a low-saturation background with high-saturation text.
- **Pending:** `secondary_container` background / `on_secondary_container` text.
- **En Route:** `primary_fixed` background / `on_primary_fixed_variant` text.
- **Completed:** `surface-container-highest` background / `outline` text.

### The ETA Card (Role-Specific)
For Drivers and Attendees, the ETA card is the most critical component. It should be a **Glassmorphic** element floating at the bottom of the map.
- **Background:** `surface` at 80% opacity + 20px blur.
- **Content:** Use `title-lg` for the "Minutes Away" and `body-sm` for the "Current Stop" subtext. 

### Map Markers
- **Active Vehicle:** A circular `primary` container with a white icon, surrounded by a 10% opacity `primary` pulse ring.
- **Stops:** Use `secondary` for the next immediate stop and `outline-variant` for all subsequent stops to create a visual path.

---

## 6. Do's and Don'ts

### Do
- **DO** use vertical white space (from the 16 or 20 spacing tokens) to separate list items instead of divider lines.
- **DO** use asymmetric layouts. Align text to the left but allow icons or status chips to float in "breathing room" to the right.
- **DO** ensure high contrast for all "on-surface" text to maintain accessibility for drivers in bright sunlight.

### Don't
- **DON'T** use 1px solid lines to separate content blocks. 
- **DON'T** use high-contrast drop shadows. They look "dated" and disrupt the calm identity.
- **DON'T** use the Amber color (`secondary`) for "Danger" or "Error"—that is reserved for the `error` token. Amber is for "Intelligence" and "Attention."