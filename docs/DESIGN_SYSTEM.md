# SchneeGlass Design System

## Purpose

`SchneeGlassDesignSystem` is the visual foundation shared by SchneeGlass Presentation surfaces.

It exists to keep visual decisions consistent and reviewable without coupling reusable styling primitives to Domain or Application state.

The design system follows three layers:

```text
Foundation tokens
    ↓
Reusable visual components / styles
    ↓
Presentation screens
```

Each layer is introduced independently so token migration, component extraction, and intentional visual redesign remain separately reviewable changes.

## Design principles

### Native macOS first

Prefer SwiftUI/macOS semantic colors, materials, typography roles, controls, focus behavior, and accessibility behavior over custom replacements.

### Safety must be visible

File-operation UI must communicate safety-relevant consequences such as no-overwrite behavior and preservation of source files. Those messages belong to Presentation semantics, not the Design System.

### Quiet desktop presence

Desktop Glasses should remain visually lightweight and avoid unnecessary decoration because they can remain visible for long periods.

### State must not rely on color alone

Meaningful states should combine text, symbols, structure, or accessibility labels rather than using color as the sole signal.

### Material is presentation, not information

Information must remain understandable if transparency/material effects are reduced by system accessibility settings.

## Dependency boundary

`SchneeGlassDesignSystem` may provide SwiftUI visual primitives and semantic values.

It must not import or interpret:

- `SchneeGlassDomain`
- `FileDomain`
- `SchneeGlassApplication`
- `SchneeGlassPresentation`
- concrete adapters
- `SchneeGlassPOSIXSupport`
- AppKit-specific application behavior

`SchneeGlassPresentation` maps Domain/Application state into user-facing semantics and then applies Design System tokens/components.

```text
Domain / FileDomain
       ↓
Application
       ↓
Presentation semantics
       ↓
Design System visuals
```

The architecture CI guard enforces this downward-only Design System dependency boundary.

## Token rules

Tokens are named by **semantic role**, not only by numeric value.

Good:

```swift
SchneeGlassRadius.glassSurface
SchneeGlassPadding.desktopGlass
SchneeGlassSpacing.fileGridColumn
```

Avoid:

```swift
radius20
spacing10
padding16
```

Two roles may intentionally have the same numeric value. They remain separate tokens when changing one should not imply changing the other.

For example, message spacing and file-grid spacing are separate semantic roles even when both are currently `10pt`.

Do not move every numeric literal into the Design System. Screen-specific geometry, one-off constraints, state-machine values, animation timing with local meaning, and values whose reusable role is unclear should stay local until a stable semantic role exists.

## Foundation namespaces

### `SchneeGlassSpacing`

Spacing between related visual elements. Examples include surface content, control groups, file grids, and interaction overlays.

### `SchneeGlassPadding`

Insets around a named surface or layout region. Padding roles remain distinct even when values currently match.

### `SchneeGlassRadius`

Corner radii for stable visual surface roles such as Glass surfaces, message banners, and Drop overlays.

### `SchneeGlassMetrics`

Stable component geometry such as menu hit frames, file icon geometry, and adaptive file-tile widths.

### `SchneeGlassTypography`

Semantic system typography roles. These use SwiftUI system fonts rather than fixed custom point sizes where possible.

## Component rules

A Design System component owns reusable **visual structure** only. It must not switch on Domain/Application state or decide user-facing business meaning.

Prefer a shared component when:

- the internal visual structure is genuinely the same on multiple surfaces
- differences can be expressed through neutral visual inputs
- extracting it reduces duplicated visual policy without introducing mode flags

Do not create a shared component merely because two views currently have similar code. Workspace/Desktop layout composition remains separate when their structure or interaction hierarchy differs.

Avoid components with branching such as:

```swift
if isDesktop { ... }
if isWorkspace { ... }
```

Prefer Presentation to supply neutral inputs:

```text
FileKind
  ↓ GlassItemPresentation
systemImage + accessibilityLabel
  ↓
SchneeGlassFileTile(systemImage:title:)
```

Interaction callbacks, context menus, Domain IDs, and application state remain owned by Presentation unless the interaction itself is a stable reusable UI primitive.

### `SchneeGlassStateMessage`

Reusable symbol/title/detail stack for Empty, Unavailable, and Failure content. The caller owns the actual copy, state mapping, surrounding layout, and text alignment policy.

### `SchneeGlassFileTile`

Reusable file-tile visuals. The caller owns FileDomain mapping, gestures, context menus, and accessibility action semantics.

`GlassItemPresentation` in `SchneeGlassPresentation` is the adapter that maps `FileKind` into the neutral symbol/accessibility inputs used around this component. This keeps `FileDomain` out of the Design System target.

## Compatibility facade

`SchneeGlassDesignTokens` is retained temporarily as a deprecated compatibility facade for the original public constants.

New production code must use the semantic namespaces. The compatibility facade may be removed only through an explicit source-compatibility decision.

## Presentation ownership

The Design System does **not** decide what `DropRejection`, `GlassContentState`, recovery state, or any other application state means to the user.

For example:

```text
DropRejection
    ↓ Presentation mapper
"Nothing will be overwritten."
    ↓ Design System
Typography / spacing / surface treatment
```

This separation prevents reusable visual components from acquiring Domain/Application dependencies.

## Visual regression policy

Design System refactors must preserve existing rendering unless a PR explicitly declares a design change.

For refactor-only Design System PRs:

- existing visual snapshots must remain unchanged
- canonical visual snapshot CI must pass in record-never mode
- visual changes require a separate, reviewable design PR

Design System component snapshots should test component variants exhaustively, while screen-level snapshots should cover representative compositions rather than every cross-product of states.
