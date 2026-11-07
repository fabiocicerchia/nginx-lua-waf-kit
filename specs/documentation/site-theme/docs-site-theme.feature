@domain:documentation @area:site-theme @from:docs/stylesheets
Feature: Branding the documentation site
  Gives readers of the docs and the GitHub Pages splash one consistent, self-contained look that loads nothing from third parties.

  Background:
    Given the documentation site and the splash page are published together, the splash at / and the rendered docs at /docs/

  @id:documentation.site-theme.001 @rule:docs.theme.shared-accent-palette @inferred @source:docs/stylesheets/extra.css#:root @questionable
  Scenario: The splash page and the docs show the same accent colours
    Given the theme's accent pair is orange #fb923c and red #ef4444
    When a reader opens the splash page and then the docs
    Then the splash page title and its GitHub button are drawn in an orange-to-red gradient
    And the docs home title and primary buttons are drawn in the same orange-to-red gradient
    And the docs header and the splash install label use the red #ef4444

  @id:documentation.site-theme.002 @rule:docs.theme.no-external-font-requests @inferred @source:docs/stylesheets/extra.css#:root
  Scenario: Reading the docs fetches no web fonts
    Given the reader's browser blocks every third-party host
    When a reader opens any docs page
    Then body text is set in the operating system's sans-serif font
    And code is set in the operating system's monospace font
    And no font is requested from any external host

  @id:documentation.site-theme.003 @rule:docs.theme.legible-links-per-scheme @inferred @source:docs/stylesheets/extra.css#[data-md-color-scheme="slate"]
  Scenario Outline: Links take the accent colour that stays readable in each colour scheme
    Given the reader's colour scheme is <scheme>
    When a reader views a docs page containing a link
    Then the page background is <background>
    And links are shown in <link colour>

    Examples:
      | scheme | background         | link colour    |
      | light  | the default white  | red #ef4444    |
      | dark   | near-black #0b0f1a | orange #fb923c |

  @id:documentation.site-theme.004 @rule:docs.theme.no-stand-in-logo @inferred @source:docs/stylesheets/extra.css#.md-header__button.md-logo
  Scenario: The docs show no logo until the project has one of its own
    Given the project has not configured a logo
    When a reader views a docs page
    Then the header shows the site name without any logo icon
    And the navigation title shows no logo icon

  @id:documentation.site-theme.005 @rule:docs.theme.wide-tables-scroll @inferred @source:docs/stylesheets/extra.css#.md-typeset table:not([class]) @questionable
  Scenario: A table wider than the screen is cut off instead of scrolling
    Given a docs page contains a table wider than the reader's screen
    When a reader views that page on a narrow screen
    Then the table is shown with rounded, bordered card edges
    And the columns past the right edge are hidden and cannot be scrolled into view
