@domain:documentation @area:site-theme @from:docs/stylesheets
Feature: Branding the documentation site
  Gives readers of the docs and the GitHub Pages splash one consistent, self-contained look that loads nothing from third parties.

  Background:
    Given the documentation site and the splash page are published together, the splash at / and the rendered docs at /docs/

  @id:documentation.site-theme.002 @rule:docs.theme.no-external-font-requests @inferred @source:docs/stylesheets/extra.css#:root
  Scenario: Reading the docs fetches no web fonts
    Given the reader's browser blocks every third-party host
    When a reader opens any docs page
    Then body text is set in the operating system's sans-serif font
    And code is set in the operating system's monospace font
    And no font is requested from any external host

  @id:documentation.site-theme.005 @rule:docs.theme.wide-tables-scroll @inferred @source:docs/stylesheets/extra.css#.md-typeset table:not([class]) @questionable
  Scenario: A table wider than the screen is cut off instead of scrolling
    Given a docs page contains a table wider than the reader's screen
    When a reader views that page on a narrow screen
    Then the table is shown with rounded, bordered card edges
    And the columns past the right edge are hidden and cannot be scrolled into view
