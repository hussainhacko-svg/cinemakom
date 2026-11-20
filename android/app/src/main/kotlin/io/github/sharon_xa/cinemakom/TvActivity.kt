package io.github.sharon_xa.cinemakom

/**
 * The TV entry (docs/TV.md). It exists only so the manifest can declare it
 * landscape and list it with LEANBACK_LAUNCHER, while [MainActivity] stays
 * portrait for phones. Everything else is [MainActivity].
 */
class TvActivity : MainActivity()
