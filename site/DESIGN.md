---
name: FAV Documentation
description: A restrained technical manual for FAV users and reviewers.
colors:
  violet: "#6d4bc3"
  violet-deep: "#4f319d"
  violet-soft: "#eee9fb"
  paper: "#f7f7fa"
  surface: "#ffffff"
  ink: "#17151d"
  muted: "#666271"
  line: "#dedce5"
  warning-ink: "#553407"
  warning-surface: "#fff5dc"
  warning-line: "#e8c67d"
typography:
  display:
    fontFamily: "Atkinson Hyperlegible, ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(3.25rem, 8vw, 6rem)"
    fontWeight: 700
    lineHeight: 1.08
    letterSpacing: "-0.035em"
  body:
    fontFamily: "Atkinson Hyperlegible, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.65
rounded:
  control: "10px"
  surface: "14px"
spacing:
  compact: "0.8rem"
  standard: "1.5rem"
  section: "clamp(3.5rem, 7vw, 6rem)"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.surface}"
    rounded: "{rounded.control}"
    padding: "0.65rem 1rem"
  note:
    backgroundColor: "{colors.violet-soft}"
    textColor: "{colors.violet-deep}"
    rounded: "{rounded.surface}"
    padding: "1.2rem 1.3rem"
---

# Design System: FAV Documentation

## Overview

**Creative North Star: “The Independent Technical Manual”**

The site reads like documentation before it reads like promotion. Large,
decisive headings establish hierarchy; quiet rules and measured columns keep
technical material easy to scan. The interface uses the FAV violet sparingly,
mainly for orientation, selection and links.

The visual system is flat, direct and calm. It avoids decorative technology
motifs, generic feature-card grids and claims unsupported by project evidence.

**Key Characteristics:**

- Cool paper ground with high-contrast ink.
- One accessible type family, self-hosted and free of runtime dependencies.
- Generous section spacing and thin structural rules.
- Plain-language copy with safety limits placed beside relevant actions.

## Colors

The palette is neutral and editorial. Violet identifies FAV without becoming a
background effect.

**The Rationed Accent Rule.** Violet marks links, navigation state and the top
rule; it does not fill large decorative areas.

## Typography

**Display Font:** Atkinson Hyperlegible, with a system sans-serif fallback.

**Body Font:** Atkinson Hyperlegible, with a system sans-serif fallback.

Display headings use bold weight, tight tracking and balanced lines. Running
text stays at 1rem or larger, with a maximum measure of 70 characters.

## Layout

The shared content width is 72rem. Landing content uses asymmetric editorial
grids; documentation pages use a sticky contents rail beside a 70ch reading
column. Below 760px, every grid becomes a single column and navigation becomes
a horizontally scrollable row without widening the page.

## Elevation & Depth

The system is flat by default. Borders, surface tone and spacing establish
hierarchy. Cards do not use shadows; the sticky header alone uses backdrop blur
to remain legible over scrolling content.

## Shapes

Buttons use 10px corners. Informational surfaces use 14px corners. Dividers are
one-pixel neutral rules. Pills and decorative geometric containers are absent.

## Components

### Buttons

Primary actions use ink on white; secondary actions invert that relationship
with a one-pixel border. Both share the same height, padding and focus ring.

### Cards / Containers

Cards are reserved for information that must remain grouped, such as release
status or a safety warning. Ordinary content uses whitespace and rules instead.

### Navigation

Navigation is text-only. The current page uses ink while inactive destinations
use muted text. On narrow screens, the row scrolls horizontally.

## Do's and Don'ts

### Do:

- **Do** explain a security boundary beside the decision it affects.
- **Do** use rules and spacing before introducing another container.
- **Do** keep body copy within the reading measure.

### Don't:

- **Don't** fabricate adoption figures, testimonials or security guarantees.
- **Don't** use gradients, glowing effects or terminal imagery as decoration.
- **Don't** turn each feature into an interchangeable icon card.
