# Twilight Palm toolbar-card hover outline

## Scope

Update only the four default New Task toolbar cards in the `twilight-palm`
skin. The affected elements are the `button.min-h-26` children of the New
Task `home-suggestions` container, scoped below
`main.main-surface.dream-skin-new-task-home-visual`.

## Behaviour

- Keep the existing dark translucent card surface, low-contrast warm border,
  layout, icon treatment, labels, and native interaction behaviour at rest.
- On hover, strengthen the existing warm-gold border into a clear, soft thin
  line and add a very subtle warm outer glow.
- Do not resize, move, replace, or otherwise alter the native buttons.
- Do not apply this treatment to query-generated suggestions, chats, work
  pages, other themes, or other skins.

## Implementation boundary

Make the presentation-only change in `skins/twilight-palm/style.css`, using a
theme-and-route-scoped hover selector. Retain the current background hover
treatment and change only the hover border and shadow values needed for the
soft warm-gold affordance.

## Verification

1. Confirm the selector targets the four `button.min-h-26` New Task cards
   only.
2. Inspect the resting and hover computed border and box-shadow values for all
   four cards in the active Twilight Palm theme.
3. Inspect a live rendered hover state and confirm the result is a restrained
   warm-gold thin outline, without geometry or interaction changes.
4. Run the relevant static skin checks and report any live-verification limit.
