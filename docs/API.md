# Cinemana API Reference

The reverse-engineered API that Cinemakom is built on. **This file is the source of truth.** The old Kotlin app (`../cinematy`) got several things wrong (sort codes, genre IDs, search encoding, subtitles), so don't trust it over this file.

**How this was verified (2026-11-19):**
- **Live probes** of every endpoint: sorting, paging, limits, errors, headers and parental levels.
- **The official web app** (`https://cinemana.shabakaty.com/home`): its JavaScript endpoint map, the parameters it builds, and its network traffic, watched in Chrome.
- **Captured responses** in `test/fixtures/`. Re-capture them with `dart run tool/capture_fixtures.dart`.
- **A field-level survey** of 862 records from 14 endpoints: types, missing and empty rates, and value formats.
- **Edge-case probes:** past-the-end pages, special characters, invalid and mixed IDs, batch limits, and 40 parallel requests.
- **Two repeatable live checks** that use the app's own code:
  - `dart run tool/api_contract_check.dart` verifies every contract in this file: field types, parser yield, server limits and media files. **Run it before each release and whenever data looks wrong.**
  - `flutter test integration_test/api_debug_test.dart -d linux` exercises every repository end to end.

Status legend: ✅ works and is used · ⚙️ works but unused · ❌ dead or broken · 🔒 needs a login (out of scope) · 🚫 excluded on purpose (zero-censorship rule).

---

## 1. Hosts

| Host | What | Notes |
|---|---|---|
| `cinemana.shabakaty.com/api/android/` | The main API | JSON over GET, plus one form POST |
| `recommend.shabakaty.com` | "More like this" recommendations | JSON POST, no login needed ✅ |
| `cnth2.shabakaty.com` | Posters, staff photos, subtitles, seek-preview sprites | Static files. Posters aren't signed, subtitles are |
| `cdn.shabakaty.com`, `cndw6.shabakaty.com`, … | Video files | Several CDN hosts. Always use the URL as given |
| `thumbnail.shabakaty.com` | Season posters | ❌ Returns 500, even for the official website |
| `rating.shabakaty.com` | Cinemana user ratings | ❌ for us: needs a `ShabakatyAppId` header whose value only exists in the web bundle. We don't use client IDs from the bundle (AGENTS.md) |
| `contwatch.shabakaty.com`, `account.shabakaty.com` | Watch progress, accounts | 🔒 Login only. Out of scope |

## 2. Conventions

### Headers
The website sends `User-Agent`, `Referer: https://cinemana.shabakaty.com/` and `Origin: https://cinemana.shabakaty.com`. **None of them are required** by the API, the image host or the video CDN (tested with no headers at all). We still send them on every request through the one shared map, `ApiClient.defaultHeaders`, in case the servers start checking.

### Parental level: always `0`
Every `level` parameter is a parental level. **`0` is the unrestricted level** and returns the full catalog: 85 banners, versus 33 at level 2 and 13 at level 3 (levels 1, 4 and 5 behave like 0). Cinemakom always sends `0`, with no setting to change it (the zero-censorship rule in AGENTS.md).

### Language
`lang` accepts `ar` or `en`. Anything else is treated as `en`. It only changes text the server localizes itself (group titles, category names, staff role). Media items always carry both `en_title` and `ar_title`.

### Kind
`videoKind` / `kind`: `1` = movies, `2` = series. Unknown codes are treated as `1`. `AdvancedSearch` uses `type=movies|series` instead.

### Sort codes (catalog `sortParam`, `videosByCategory…` `orderby`)
Verified by checking the order of live results:

| Code | Meaning | `SortOrder` |
|---|---|---|
| `desc` | Recently **uploaded** first (the default) | `recentlyAdded` |
| `asc` | Oldest uploads first | `oldestAdded` |
| `r_desc` | Newest **release year** first. **Not "top rated"** (the Kotlin app got this wrong) | `newestRelease` |
| `stars_desc` | Highest `stars` first. **Not used: the app has no ratings** (AGENTS.md) | none |
| `views_desc` | **Most watched** first | `mostViewed` |
| `r_asc`, `rating_desc`, `title_asc`, `title_desc`, … | Listed in the website's code, but unreliable or ignored | not used |

Any unknown code silently falls back to `desc`. **`AdvancedSearch` ignores sorting entirely**, including on the official website.

### Paging (each endpoint differs)

| Endpoint | Scheme | Page size |
|---|---|---|
| `video/V/2/…/pageNumber/{n}` (catalog, title search) | 0-based page | `itemsPerPage`, **capped at 99** |
| `latestMovies` / `latestSeries` `…/page/{n}/` | 0-based page | `itemsPerPage` (24 by default, 100 works) |
| `featuredMovies …/page/{n}` | 0-based page | `itemsPerPage` (12) |
| `videoListPagination …/page/{n}` | 0-based page | 12 |
| `videosByCategory`, `videosByCategoryAndLanguage` | **item offset** (`offset=30` skips 30 items); the response's `offset` is the next one | 30 |
| `AdvancedSearch` | 0-based `page` | 12 |
| `newlyVideosItems/…/offset/{n}/` | **`n` is a count, not an offset**: returns `n` items, capped at 12 | ≤ 12 |

**The end of a list:** every endpoint answers `200` with an empty list past the end. `videosByCategory…` keeps sending a larger `offset` even then (`offset=999999` → next `1000029`), so **stop paging on an empty page or one shorter than the page size**, never on the absence of `offset` (`OffsetPage.hasMore`). `itemsPerPage=0` gives 10. A negative page or offset is treated as 0.

### Responses
- **IDs** are under `nb`, as strings. `"0"` means "none" (e.g. `rootSeries: "0"`).
- **Numbers usually arrive as strings** (`"7.5"`), but not always (`videoCommentsNumber` is a number). The string `"null"` also appears.
- **Ratings and counters aren't used.** The app has no ratings (AGENTS.md), so `stars`, `rate`, `filmRating`, `seriesRating`, `Likes`, `DisLikes` and `videoLikesNumber` are never parsed. For the record: `stars` is a 2–9.5 score, `rate` is an unrelated large number (e.g. `1565775`), and **`videoViewsNumber` is always `0`** (even for the most-watched titles), so view counts can't be shown either.
- **Titles are often untranslated:** 58% of records have identical `en_title` and `ar_title`, and some `en_title`s are in Arabic. Show `ar_title` in Arabic and `en_title` in English, and don't assume either one is in its own language.
- **`custom_en_title` / `custom_ar_title`** on group items are the **group's** name, not the item's. Ignore them.
- **Content types are unreliable**, so the client reads bodies as text and decodes the JSON itself.
- **Caching:** API responses have `Cache-Control: max-age=600`, so caching for 10 minutes is safe.
- **Concurrency:** 40 parallel requests all succeeded (no rate limiting), but the server slows to a crawl (~20 s with 20 at once). `ApiClient` runs at most 6 requests at a time and retries a failed GET once, on network errors, timeouts and 5xx only.
- **Signed URLs:** video and subtitle URLs carry `AWSAccessKeyId`, `Expires` and `Signature`, and **expire after about 5 days**. Never store them: refetch `transcoddedFiles` / `translationFiles` before playing or downloading. Poster URLs aren't signed.

### Errors

| Situation | Response |
|---|---|
| Unknown endpoint | `404 {"status": false, "error": "Unknown method."}` |
| `allVideoInfo` for an unknown or invalid ID | `400 []` or `400` with an empty body |
| `videoSeason` for an unknown ID | `400`, empty body |
| `transcoddedFiles` for an unknown ID | `200`, **empty body** |
| `translationFiles` for an unknown ID | `200` with the `defaultImages/loading.gif` placeholders |
| `staff`, `relatedVideos` for an unknown ID | `200 []` |
| Title search with a raw `=` or `+` in the path | `400` (see Search) |

## 3. Data model

### Media items
Lists and details share one record shape with 70+ fields. The useful ones:

| Field | Meaning |
|---|---|
| `nb` | ID |
| `en_title`, `ar_title`, `other_title` | Titles. `other_title` is the original-language title |
| `en_content`, `ar_content` | Synopsis |
| `kind` | `1` movie, `2` series |
| `year`, `mDate` | Release year / date |
| `stars` | Rating, 0–10 |
| `duration` | Seconds, as a string with decimals (`"6010.03"`) |
| `rootSeries`, `season`, `episodeNummer` | Series structure (two m's in `episodeNummer`) |
| `imgObjUrl`, `imgMediumThumbObjUrl`, `imgThumbObjUrl` | Images (see below) |
| `categories` | `[{en_title, ar_title}]` |
| `imdbUrlRef`, `trailer` | IMDb (sometimes MyAnimeList) link, YouTube trailer |
| `published`, `updateDateTime`, `videoUploadDate` | Upload timestamps |

### Series and episodes
A series has **no separate record**. It is represented by its **first episode (S1E1)**, which has `rootSeries: "0"`. Every other episode has `rootSeries` set to S1E1's `nb`, so **series ID = `rootSeries`, or the item's own `nb` when `rootSeries` is `"0"`** (`MediaItem.seriesId`). The website resolves it the same way.
- `latestSeries` and the series catalog list S1E1 items.
- `videoSeason` returns every episode **unsorted** (Friends: 234 episodes, starting at S9E1). Sort by season, then episode.
- **Episodes have no titles of their own**: each one repeats the series name. They have **no per-episode synopsis** either (it repeats too). **Images are per season** (Friends has 10 unique images across 234 episodes). The UI should label episodes "Episode N" and use the season image.

### Images
All posters are portrait 2:3. Measured on Avengers: Infinity War:

| Field | Size | Weight | Use |
|---|---|---|---|
| `imgThumbObjUrl` | 100×150 | ~6 KB | Tiny thumbnails, blurred placeholders |
| `imgMediumThumbObjUrl` | 293×439 | ~40 KB | Cards and grids |
| `imgObjUrl` | **2000×3000** | **~1.5 MB** | Details and hero only, **decoded at display size** (`cacheWidth`). Never in lists |

- **Banner images are different:** `banner` items have a **wide** `imgObjUrl` (the `_cover.jpg`, about 2.7:1, e.g. 3881×1437, 1350×500), the only landscape artwork the API offers. Their `imgMediumThumbObjUrl` is a **relative path** (`vascin-poster-images/….jpg`) to the normal 293×439 portrait poster. Resolve it against `https://cnth2.shabakaty.com/` (`resolveImageUrl`, `parseBanners`). The fields `img`, `imgThumb` and `imgMediumThumb` are bare file names: ignore them.
- **Staff photos:** `staff_img` / `staff_img_medium_thumb` are 293×439, `staff_img_thumb` is 100×150. They're often `null`.
- There are **no backdrops** other than banners.

### Streams (`transcoddedFiles`)
`[{name, resolution, container, transcoddedFileName, videoUrl}]`. Every stream seen so far is **progressive MP4** (no HLS), at `240p` / `360p` / `480p` / `720p` / `1080p`, and **`2160p`** on some titles. Servers answer byte ranges with `206`. Sizes are large (1080p ≈ 3 GB for 2.5 h). No headers are required. For a series, request an **episode** ID.

### Subtitles (`translationFiles`)
`{arTranslationFilePath, enTranslationFilePath, translations: [{id, name, type, extention, file}]}`
- **Each language comes twice, as `srt` and as `vtt`.** The key is spelled `extention`.
- Files are **UTF-8 without a BOM**. Line endings are mixed (`\n` and `\r\n`).
- When there are no subtitles, the path fields hold the placeholder **`defaultImages/loading.gif`**. Only accept real `http(s)` subtitle files.

### Intro skipping
`allVideoInfo.introSkipping`: `[{start, end, control_level}]` in seconds. These are **real intro ranges**, sometimes two (a cold open, then the intro). Example: Game of Thrones `0→8 s` and `241→348 s`. Use it for the "Skip intro" button.

### Seek-bar previews (`video_thumbnails`)
`{videoThumbnails: [{sprite_url, url, order, height}], status}`. `status` is `204` with an empty list when a title has none. Popular titles have them; many new ones don't.
- Each sheet is a PNG **10×10 grid of 120×68 frames**, about **one frame every 10 s**, in row-major order. The last sheet is shorter.
- Example: Friends 1332 s → 2 sheets, the second 4 rows tall.
- Prefer `sprite_url`, which is absolute. Otherwise prefix `url` with `https://cnth2.shabakaty.com/`.
- See `SeekPreview.frameAt`.

---

## 4. Endpoints

### Home and catalog

| | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `banner/level/0` | Hero banners (85). Wide images. `link` points to the website and sometimes carries `lastEpisodeVideoID` for series |
| ✅ | GET | `videoGroups/lang/{lang}/level/0` | Curated rows: `{groups: [{groupsID, title, content: [media], hasPagination, analytics}]}`. **The ID key is `groupsID`.** Titles are localized |
| ✅ | GET | `videoListPagination/groupID/{groupsID}/level/0/itemsPerPage/12/page/{page}` | "See all" for a group |
| ✅ | GET | `featuredMovies/level/0/itemsPerPage/12/page/{page}` | Featured titles |
| ✅ | GET | `latestMovies/level/0/itemsPerPage/24/page/{page}/` | Newest movies |
| ✅ | GET | `latestSeries/level/0/itemsPerPage/24/page/{page}/` | Newest series (S1E1 items) |
| ✅ | GET | `newlyVideosItems/level/0/offset/12/` | The 12 newest uploads (movies and episodes) |
| ✅ | GET | `video/V/2/itemsPerPage/{n}/level/0/videoKind/{kind}/sortParam/{sort}/pageNumber/{page}` | **The main catalog.** Powers top rated, most viewed, newest release and recently added, for movies or series |
| ❌ | GET | `latestVideosItems/level/0/offset/{n}/` | The website's "new releases". Returns `n` items and duplicates `newlyVideosItems`. Not used |
| ❌ | GET | `popularFilms/kind/{D,W,M,Y}/level/0/page/{page}` | Always `[]` |

### Categories and languages

| | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `mainCategories?lang=` | The 15 main genres: `[{nb, title}]`. **84** Action, **56** Adventure, **57** Animation, **59** Comedy, **60** Crime, **61** Documentary, **62** Drama, **67** Fantasy, **70** Horror, **76** Mystery, **77** Romance, **78** Sci-Fi, **79** Sport, **80** Thriller, **89** Western. These are also the app's `fallbackGenres` |
| ✅ | GET | `subCategories?lang=` | 34 secondary genres (Biography, Family, Supernatural, Anime tags…), same shape |
| ✅ | GET | `category` | 50 categories with both `en_title` and `ar_title`. Includes non-genres (e.g. 149 "Program") that return nothing |
| ✅ | GET | `categoryLangFreqVideo` | Each category with a `langArray: [{catNb, langNb, lang_en_title, lang_ar_title, langFreq, langFreqSeries}]` (823 pairs). `langFreq` is often `""`, so treat it as 0 |
| ✅ | GET | `videosByCategory?categoryID=&orderby=&videoKind=&offset=&level=0` | `{info: [media], offset: next}`, 30 per page |
| ✅ | GET | `videosByCategoryAndLanguage?category_id=&language_id=&orderby=&videoKind=&offset=&level=0` | Same shape. `language_id` is `langNb`. The website's Anime pages use `category_id=57` (Animation) with `orderby=desc` |

### Search

| | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `video/V/2/itemsPerPage/30/video_title_search/{q}/itemsPerPage/30/pageNumber/{page}/level/0` | Title search across movies and series, with good relevance. **Encoding:** `q` = percent-encode(base64(URL-encode(query))). A raw `=` padding or `+` makes the server answer **400**: "the dark knight" and "spider-man" both failed in the Kotlin app. Verified with spaces, `'`, `&`, `:`, `-`, `%`, `+`, `#`, Arabic, accented and CJK text. Leading and trailing spaces are ignored. Search is fuzzy (`c++` matches loosely), and an empty segment returns something arbitrary, so never send an empty query |
| ✅ | GET | `AdvancedSearch?level=0&…` | Filters, verified live: `videoTitle`, `staffTitle` (actor or director name, e.g. "Christopher Nolan"), `type=movies\|series`, `category_id` (**not** `category`, which returns nothing), `year=from,to` (the website always sends `1900,<current year>`), `star` (minimum rating, **not used**: no ratings), `page`. Arabic `staffTitle` works, an unknown `type` is ignored, and an empty `videoTitle` returns a default list. **No sorting.** 12 per page |

### Media details and playback

| | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `allVideoInfo/id/{id}` | The full record. Adds `actorsInfo`, `directorsInfo`, `writersInfo` (`[{nb, name, role, staff_img…}]`, role `1` director, `2` actor, `3` writer), `categories`, `videoLanguages` (an object or a list of `{en_title, ar_title}`), `introSkipping`, `trailer`, `imdbUrlRef`, `videoViewsNumber`, `videoLikesNumber`, `videoDisLikesNumber`, `castable`, and `translations` (same as `translationFiles`) |
| ✅ | GET | `transcoddedFiles/id/{id}` | Streams (see §3) |
| ✅ | GET | `translationFiles/id/{id}` | Subtitles (see §3) |
| ✅ | GET | `videoSeason/id/{seriesId}` | All episodes, unsorted |
| ✅ | GET | `videoSeasonNumber/id/{seriesId}` | `[{season: "1"}, …]` |
| ✅ | POST | `https://recommend.shabakaty.com/api/recommendation/recommend` | **"More like this", as the website uses it.** JSON body `{MovieId, MovieName?, ReProcessIfExpired: true}`. Returns `{movieId, movieName, recommendations: [media…], expirationDate}`, 10 items, each with a `distance_type` (`collection` = same franchise, `staff_at_least_2` = shared cast). `MovieId` can be a string or a number. An episode ID gives the same results as its series root. `MovieName` doesn't change the results. An unknown ID returns an empty list. Usually under 300 ms. No login |
| ⚙️ | GET | `relatedVideos/id/{id}/kind/{kind}/level/0` | Older "similar titles" (10 items). The website no longer calls it. The app uses it only as a fallback |
| ✅ | GET | `video_thumbnails/video_id/{id}` | Seek-preview sprites (see §3) |
| ✅ | POST | `getVideosByIds` | Form body `ids=[id1, id2, …]` (the brackets are required). Fresh metadata for many titles at once, e.g. to refresh favorites and history. **At most 40 IDs**: 41 or more answer `400`. The response **keeps the request order** and repeats duplicates. Unknown numeric IDs are skipped, but **a single non-numeric ID empties the whole response**, and `[]` answers 400. `MediaRepository.byIds` sends only de-duplicated numeric IDs, 40 at a time |
| ✅ | GET | `staff/actorID/{staffId}/lang/{lang}/level/0` | Person page: `{title, role, img*ObjUrl, items: [media]}` |
| ✅ | GET | `faqQuestion` | 29 FAQ entries, bilingual |
| 🚫 | GET | `skippingDurations/id/{id}` | Parental-filter scene skips (`{start: [], end: []}`), not intros. Excluded under zero censorship |
| 🚫 | GET | `checkVideoParentalLevel/id/{id}` | Parental check. Excluded |
| ❌ | GET | `videoComment/id/{id}/limit/{n}/offset/{n}` | Always `[]`. Comments are **switched off server-wide** (`showComments: false` on every title) |
| ❌ | GET | `collectionsId/`, `collectionVideos/collectionID/{id}/level/0` | Always `[]`, even for collection IDs the recommendation service reports |
| ❌ | POST | `https://thumbnail.shabakaty.com/api/series/seasonposters` `{RootSeries}` | Returns 500, also on the website |

### Login only (🔒 out of scope)
`history`, `continueWatching`, `addToHistory`, `removeFromHistory`, `get_subscriptions`, `add_subscriptions`, `remove_subscriptions`, `get_subscription_status`, `memberCheckVideoStatus`, `addLike`, `increaseNumberOfView`, `highlightEpisode`, `addComment`, `removeComment`, `reportIssue`, `get_notifications`, `resetNewNotifications`, `userSettings`, `changeParentalLevel`, `UserTranslationSettings`, everything on `contwatch.shabakaty.com` and `account.shabakaty.com`, and rating writes on `rating.shabakaty.com`.

---

## 5. What the website calls (for reference)

**Title page** (`/video/{lang}/{id}`):
1. `allVideoInfo`
2. the recommendation service
3. `transcoddedFiles`
4. `translationFiles`
5. `video_thumbnails`
6. `videoSeason` and `videoSeasonNumber` (series only)
7. `seasonposters`, which fails with 500

It also calls `checkVideoParentalLevel` and `skippingDurations` (excluded for us) and the rating summary (needs the app ID).

**Home** uses `banner`, `videoGroups` and the category endpoints. The **Anime** section uses `videosByCategoryAndLanguage` with `category_id=57`.

## 6. Keeping this reliable
- **The parsers never throw.** They skip bad records, and `tool/api_contract_check.dart` checks that no *valid* record is skipped (parser yield = raw count).
- **Fixtures are real responses** (lists trimmed to 6 items, signed URLs redacted). Parser tests run against them, plus inline edge cases.
- **When the API changes:**
  1. Run the contract check.
  2. Re-capture the fixtures and diff them.
  3. Update this file, the parsers and the tests together.

## 7. Open questions
- `introSkipping.control_level` is always `"3"` so far. Its meaning is unknown, and the app ignores it.
- `r_asc` and `rating_desc` behave oddly. Avoid them.
- The 2160p stream is listed only on some titles. Check it plays before offering "4K".
