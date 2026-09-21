# ``TabBarMenu``

Prepare tab bar interactions and receive completed selections, including More content.

## Overview

TabBarMenu adds tap and long-press menus to `UITabBarController`, with support
for both `UITab` and classic `viewControllers` configurations.

Set `menuDelegate` to a ``TabBarMenuDelegate`` and return a
``TabBarMenuPresentation`` from `prepareFor:on:` to show a menu. Use the
delegate's `didSelect` callback to handle selections and reselections, including
content displayed through More.

See <doc:UsingTabBarMenu> for interaction rules, selection handling, and
presentation options, or <doc:MigratingFrom0_5> to update an existing integration.

> Important: TabBarMenu relies on undocumented UIKit APIs and runtime behavior.
> Evaluate that constraint before using it in an App Store-bound app.

## Topics

### Guides

- <doc:UsingTabBarMenu>
- <doc:MigratingFrom0_5>

### Preparing Interactions

- ``TabBarMenuDelegate``
- ``TabBarInteraction``
- ``TabBarItem``

### Configuring Presentation

- ``TabBarMenuPresentation``
- ``TabBarMenuAnchorPlacement``
- ``TabBarMenuConfiguration``
