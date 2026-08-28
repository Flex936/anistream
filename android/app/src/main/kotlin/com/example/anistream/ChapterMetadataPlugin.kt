package com.anistream.app // TODO: replace with your actual applicationId package

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.extractor.metadata.Chapter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Reads MKV/MP4 chapter markers via Media3's own Chapter metadata support
 * (androidx.media3.extractor.metadata.Chapter, shipped in media3-extractor
 * 1.11.0). Confirmed directly against a real anistream-server stream that
 * Matroska chapters arrive as ChapterImpl instances, not the older
 * id3.ChapterFrame class — this filters on the Chapter INTERFACE, not any
 * one concrete implementation, so it keeps working regardless of which
 * concrete class a given container format ends up using.
 *
 * Unlike SubtitleParserPlugin, this can't operate on already-in-memory
 * bytes — Chapter metadata is only populated as a side effect of Media3
 * actually opening and preparing the container, so this spins up a
 * throwaway ExoPlayer purely to read that metadata, then releases it. The
 * real, on-screen VideoPlayerController (owned by the video_player
 * plugin) is a separate ExoPlayer instance under the hood with no
 * supported way for another plugin to reach into it, so this necessarily
 * opens the stream URL a second time. Confirmed safe against
 * anistream-server's video endpoint specifically, which already hands out
 * an independent torrent.Reader per HTTP request for exactly this kind of
 * concurrent-range-request case (see main.go's serveVideo).
 *
 * Chapter.getEndTimeMs() came back C.TIME_UNSET for every marker tested
 * against a real release — most real-world files only set a chapter's
 * start, matching what loadChapters() already has to handle for the mpv
 * path. This plugin deliberately does NOT try to derive end times itself;
 * it hands back raw (title, start) markers only, and
 * theater_data.dart's buildChaptersFromRaw does the sorting +
 * end-time-inference once, the same way for every chapter source.
 * Format.metadata also does not come back sorted by start time —
 * confirmed against the same real file — so this doesn't assume any
 * particular order either; sorting is buildChaptersFromRaw's job, not
 * this plugin's.
 *
 * Registration: call ChapterMetadataPlugin.register(flutterEngine,
 * applicationContext) from MainActivity.configureFlutterEngine().
 */
@UnstableApi
object ChapterMetadataPlugin {
    private const val CHANNEL = "anistream/chapter_parser"
    private const val TAG = "ChapterMetadataPlugin"

    // Long enough for Media3 to resolve container metadata off a torrent
    // stream that's only just started buffering; short enough that a
    // genuinely dead/unreachable URL doesn't hang the Dart caller forever.
    private const val TIMEOUT_MS = 15_000L

    private data class ChapterMarker(
        val startMs: Long,
        val title: String?,
        val hidden: Boolean,
    )

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractChapters" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("bad_args", "url is required", null)
                        return@setMethodCallHandler
                    }
                    extractChapters(context, url, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun extractChapters(context: Context, url: String, result: MethodChannel.Result) {
        Log.i(TAG, "Probing chapters for $url")

        val mainHandler = Handler(Looper.getMainLooper())
        val player = ExoPlayer.Builder(context).build()

        // Keyed by (start, title) so an identical marker reported more
        // than once — confirmed this happens, both across track groups
        // and across repeated onTracksChanged firings — collapses to one
        // entry instead of duplicating in the list Dart receives.
        val found = LinkedHashMap<Pair<Long, String?>, ChapterMarker>()

        // Guards against onTracksChanged firing more than once (it does,
        // repeatedly, for as long as the player keeps running) and
        // against the timeout and a real callback racing each other —
        // only the first caller of finish() actually resolves `result`.
        var finished = false

        fun finish() {
            if (finished) return
            finished = true
            mainHandler.removeCallbacksAndMessages(null)
            val chapters = found.values.map {
                mapOf("startMs" to it.startMs, "title" to it.title, "hidden" to it.hidden)
            }
            Log.i(TAG, "Resolved ${chapters.size} chapter marker(s)")
            result.success(chapters)
            player.release()
        }

        mainHandler.postDelayed({
            Log.w(TAG, "Timed out waiting for chapter metadata")
            finish()
        }, TIMEOUT_MS)

        player.addListener(object : Player.Listener {
            override fun onTracksChanged(tracks: Tracks) {
                for (group in tracks.groups) {
                    val trackGroup = group.mediaTrackGroup
                    for (i in 0 until trackGroup.length) {
                        val metadata = trackGroup.getFormat(i).metadata ?: continue
                        for (j in 0 until metadata.length()) {
                            val entry = metadata.get(j)
                            if (entry is Chapter && entry.startTimeMs != C.TIME_UNSET) {
                                val marker = ChapterMarker(
                                    startMs = entry.startTimeMs,
                                    title = entry.title?.value,
                                    hidden = entry.isHidden,
                                )
                                found[marker.startMs to marker.title] = marker
                            }
                        }
                    }
                }
                // Only resolves once real chapter data has actually shown
                // up — an early, chapter-less onTracksChanged firing (a
                // real possibility while a torrent stream is still
                // resolving tracks) shouldn't finish() with an empty
                // result while a later firing might still bring chapters.
                // The timeout above is what covers the genuinely-no-
                // chapters case.
                if (found.isNotEmpty()) {
                    finish()
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.w(TAG, "ExoPlayer error while probing chapters: ${error.message}")
                finish()
            }
        })

        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
    }
}