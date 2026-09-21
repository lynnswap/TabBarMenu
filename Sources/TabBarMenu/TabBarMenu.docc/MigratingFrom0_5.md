# Migrating from 0.5.x

Update menu preparation and selection handling for the unified delegate API.

## Overview

The API has breaking changes from 0.5.x. Update existing integrations as follows:

- Replace the individual tab and `menuForMoreTabWith` methods with
  `prepareFor:on:` and switch over `TabBarItem`.
- Return `TabBarMenuPresentation` instead of `UIMenu`.
- Move anchor placement and button element-order customization into the returned
  presentation. The presentation delegate and `.manual` placement are removed.
- Replace menu closures that call `selectTabContent` with `selectionAction(for:)`
  when they should trigger user-selection behavior.
- Move shared selection/reselection handling to the new `didSelect` callback.
  Keep programmatic `selectTabContent` calls for silent display synchronization.
- `TabBarMenuDelegate` is a Swift protocol with default implementations. The
  Objective-C content delegate and deprecated view-controller delegate alias
  are removed; classic view-controller support uses the same delegate.
