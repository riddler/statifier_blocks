### Fixed

- A card's title no longer breaks mid-word when the card carries several
  controls: the title column keeps a minimum of 6.5 times `--sb-text-md`, the
  hidden controls yield their width to it at rest, and on hover or selection
  they wrap inside the space left rather than squeezing the title.
