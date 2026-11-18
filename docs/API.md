# Cinemana API Reference

This file is the API reference for the Flutter frontend. Sources:
- the existing Kotlin app (`app/src/main/java/com/example/cinematy/network/ApiService.kt`)
- the endpoint map in the official web frontend bundle (`cinemana.shabakaty.com/home`, `main.*.js`)

The endpoints marked ✅ were tested live on 2026-11-18.

## Basics

**Base URL:** `https://cinemana.shabakaty.com/api/android/`

**Headers** (the Kotlin app sends these on API calls, images, video streams and downloads):
```
User-Agent: Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36
Referer: https://cinemana.shabakaty.com/
Origin: https://cinemana.shabakaty.com
```

**Common parameters**
- `level`: parental level. Always `0` for public content.
- `videoKind` / `kind`: `1` = movies, `2` = series.
- `sortParam` / `orderby`: `desc` = newest, `r_desc` = top rated.
- `lang`: `ar` or `en`.
- Paging is inconsistent. Endpoints use `page`, `pageNumber` or `offset`, and both 0-based and 1-based counting. Check each endpoint.

**Response quirks**
- IDs are under `nb`. Titles are `en_title`, `ar_title` and `other_title`.
- Images: `imgObjUrl` (full size), `imgMediumThumbObjUrl` (cards), `imgThumbObjUrl` (small).
- The episode field is spelled `episodeNummer` (two m's).
- Rating fields: `stars`, `rate`, `filmRating`, `seriesRating`.
- Some URLs come back with `\/` escapes.
- Errors are usually HTTP 400 with `{msg}`. Empty results are usually `[]` with HTTP 200.

---

## Home and catalog

| Status | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `banner/level/{level}` | Hero banners |
| ✅ | GET | `videoGroups/lang/{lang}/level/{level}` | Curated groups: `[{id,title,content:[media]}]` |
| ✅ | GET | `videoListPagination/groupID/{groupId}/level/{level}/itemsPerPage/12/page/{page}` | **New.** Paged items for one group. Page is 0-based (page 1 returned `[]` for a small group) |
| ✅ | GET | `featuredMovies/level/{level}/itemsPerPage/12/page/{page}` | **New.** Featured items |
| ✅ | GET | `latestMovies/level/{level}/itemsPerPage/24/page/{page}/` | **New.** Latest movies. Includes `published` and `updateDateTime` |
| ✅ | GET | `latestSeries/level/{level}/itemsPerPage/24/page/{page}/` | **New.** Latest series |
| ⚠️ | GET | `latestVideosItems/level/{level}/offset/{offset}/` | **New.** Returned `[]` at offset 0 |
| ✅ | GET | `newlyVideosItems/level/{level}/offset/12/` | Already in the Kotlin app |
| ✅ | GET | `video/V/2/itemsPerPage/{n}/level/{level}/videoKind/{kind}/sortParam/{sort}/pageNumber/{page}` | Main catalog. Already in the Kotlin app |
| ⚠️ | GET | `popularFilms/kind/{period}/level/{level}/page/{page}` | **New.** The web app passes period `"M"` (month). D, W, M and Y all returned `[]`, so it may need a login or be unused |

## Categories and languages

| Status | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `category` | **New.** Flat list of about 50 categories: `nb, ar_title, en_title, description, img*ObjUrl…` |
| ✅ | GET | `mainCategories?lang=` | |
| ✅ | GET | `subCategories?lang=` | |
| ✅ | GET | `categoryLangFreqVideo` | The categories again, plus `langArray: [{catNb, langNb, lang_ar_title, lang_en_title, langFreq, langFreqSeries}]`. Use it to build a "genre × language" filter |
| ✅ | GET | `videosByCategory?categoryID=&orderby=&videoKind=&offset=&level=` | |
| ✅ | GET | `videosByCategoryAndLanguage?category_id=&language_id=&orderby=&videoKind=&offset=&level=` | **New.** `language_id` comes from `langNb`. The web app uses this for its animation movie and series sections |

## Search

| Status | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `video/V/2/itemsPerPage/{n}/video_title_search/{b64}/itemsPerPage/{n}/pageNumber/{page}/level/{level}` | `b64` = base64 of the URL-encoded query (spaces as `%20`) |
| ✅ | GET | `AdvancedSearch?level=0&<filters>` | Filters the web app uses: `videoTitle`, `staffTitle`, `type` (`movies`/`series`), `category`, `category_id`, `year` (`from,to`), `star` (minimum rating), `sort`, `page` |

## Media details and playback

| Status | Method | Path | Notes |
|---|---|---|---|
| ✅ | GET | `allVideoInfo/id/{id}` | The full record. Includes useful fields the Kotlin app ignores: `actorsInfo`, `directorsInfo`, `writersInfo` (`[{nb,name,role,staff_img,staff_img_thumb,staff_img_medium_thumb}]`), `categories`, `videoLanguages`, `duration`, `trailer`, `imdbUrlRef`, `introSkipping {start,end,control_level}`, `skippingDurations {start,end}`, `hasIntroSkipping`, `videoViewsNumber`, `videoLikesNumber`, `videoCommentsNumber`, `rootSeries`, `season`, `episodeNummer`, `castable` |
| ✅ | GET | `transcoddedFiles/id/{id}` | Stream qualities: `[{name,resolution,container,transcoddedFileName,videoUrl}]` |
| ✅ | GET | `translationFiles/id/{id}` | Subtitles |
| ✅ | GET | `videoSeason/id/{seriesId}` | All episodes of a series |
| ✅ | GET | `videoSeasonNumber/id/{seriesId}` | **New.** List of season numbers: `[{season}]`. Good for a season picker that loads quickly |
| ✅ | GET | `relatedVideos/id/{id}/kind/{kind}/level/{level}` | **New.** About 10 similar titles ("More like this") |
| ✅ | GET | `skippingDurations/id/{id}` | **New.** `{start:[…], end:[…]}` for a skip-intro/outro button |
| ✅ | GET | `video_thumbnails/video_id/{id}` | **New.** `{videoThumbnails:[…], status}` for seek-bar previews. Was empty on the title tested |
| ✅ | GET | `checkVideoParentalLevel/id/{id}` | **New.** `{status}` |
| ✅ | POST | `getVideosByIds` | **New.** Form body `ids=[id1, id2, …]`. Fetches several items at once, which helps refresh favorites and history stored on the device |
| ✅ | GET | `staff/actorID/{staffId}/lang/{lang}/level/{level}` | **New.** Actor or director page: `{title, role, img*ObjUrl, items:[media]}` |
| ✅ | GET | `videoComment/id/{id}/limit/{limit}/offset/{offset}` | **New.** Comments. Reading works without a login |
| ⚠️ | GET | `collectionsId/` | **New.** Returned `[]` |
| ⚠️ | GET | `collectionVideos` | **New.** Returned 400 without parameters. The required parameters are still unknown |
| ✅ | GET | `faqQuestion` | **New.** FAQ entries: `nb, ar_title, en_title, ar_content, en_content, categoryName…` |

## Endpoints that need a login (not tested)

The web app calls these as a logged-in Shabakaty user. They are only needed if the app adds sign-in, so none of them were tested.

`history`, `continueWatching/level/{level}/itemPerPage/12/page/{page}`, `addToHistory`, `removeFromHistory`,
`get_subscriptions`, `add_subscriptions`, `remove_subscriptions`, `get_subscription_status`,
`memberCheckVideoStatus/id/{id}`, `addLike`, `increaseNumberOfView`, `highlightEpisode`,
`addComment`, `removeComment`, `reportIssue`, `get_notifications`, `resetNewNotifications`,
`userSettings/lang/{lang}`, `changeParentalLevel`, `UserTranslationSettings`

There is also a separate ratings service: `POST https://rating.shabakaty.com/api/targets/rating-summary-by-targets-types`. Its request body format was not captured.
