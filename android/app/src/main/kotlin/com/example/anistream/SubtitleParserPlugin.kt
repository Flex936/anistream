package com.anistream.app // TODO: replace with your actual applicationId package

import android.graphics.Typeface
import android.text.Layout
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import android.util.Log
import androidx.media3.common.text.Cue
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.SubtitleParser
import androidx.media3.extractor.text.ssa.SsaParser
import androidx.media3.extractor.text.ttml.TtmlParser
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Media3's own subtitle decoders to Dart. TtmlParser/SsaParser
 * are both real, standalone SubtitleParser implementations in
 * androidx.media3:media3-extractor — see
 * https://developer.android.com/media/media3/exoplayer/supported-formats
 * ("Standalone subtitle formats") — used here with no ExoPlayer/View
 * attached at all: just parse-bytes-in, cues-out. Both classes are
 * annotated @UnstableApi upstream, hence the file-level opt-in below.
 *
 * Swapping ASS -> TTML end to end is exactly the branch in parserFor()
 * below (paired with the Dart-side kSubtitleFormat constant in
 * exo_theater_screen.dart, and the Go server's SubtitleFormat in
 * subtitle_extractor.go) — nothing else here changes.
 *
 * Registration: call SubtitleParserPlugin.register(flutterEngine) from
 * MainActivity.configureFlutterEngine(). Not a full FlutterPlugin — this
 * is scoped internally to this app, not meant for standalone reuse, so
 * a plain object + MethodChannel is simpler than the full plugin
 * registration ceremony.
 */
@androidx.media3.common.util.UnstableApi
object SubtitleParserPlugin {
    private const val CHANNEL = "anistream/subtitle_parser"
    private const val TAG = "SubtitleParserPlugin"

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "parseSubtitle" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val format = call.argument<String>("format")
                    if (bytes == null || format == null) {
                        result.error("bad_args", "bytes and format are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(parse(bytes, format))
                    } catch (e: Exception) {
                        Log.e(TAG, "Subtitle parse failed", e)
                        result.error("parse_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun parserFor(format: String): SubtitleParser = when (format) {
        "ass" -> SsaParser()
        "ttml" -> TtmlParser()
        else -> throw IllegalArgumentException("Unsupported subtitle format: $format")
    }

    private fun parse(bytes: ByteArray, format: String): List<Map<String, Any?>> {
        val parser = parserFor(format)
        val out = mutableListOf<Map<String, Any?>>()
        Log.i(TAG, "Parsing ${bytes.size} bytes as \"$format\" using ${parser::class.simpleName}")

        // Fresh parser instance per call, entire standalone file handed
        // to parse() in one shot — the same "whole sideloaded file"
        // contract these classes are built for (see
        // MediaItem.SubtitleConfiguration's sideloading docs), so no
        // reset() is needed between calls: a freshly constructed parser
        // has no prior state to reset.
        parser.parse(bytes, SubtitleParser.OutputOptions.allCues()) { cuesWithTiming: CuesWithTiming ->
            val startMs = cuesWithTiming.startTimeUs / 1000
            // NOTE: durationUs is my best-confidence read of
            // CuesWithTiming's current field name, not fetched fresh
            // from source this session — if the compiler disagrees,
            // this is the one line most likely to need adjusting.
            val endMs = startMs + (cuesWithTiming.durationUs / 1000)

            for (cue in cuesWithTiming.cues) {
                out.add(cueToMap(cue, startMs, endMs))
            }
        }
        Log.i(TAG, "Produced ${out.size} styled cues from \"$format\" input")
        return out
    }

    private fun cueToMap(cue: Cue, startMs: Long, endMs: Long): Map<String, Any?> = mapOf(
        "startMs" to startMs,
        "endMs" to endMs,
        "runs" to extractRuns(cue.text),
        "line" to unsetToNull(cue.line),
        "lineAnchor" to cue.lineAnchor,        // sent, unused Dart-side in v1 — see styled_subtitle_view.dart
        "position" to unsetToNull(cue.position),
        "positionAnchor" to cue.positionAnchor, // same
        "textAlignment" to alignmentName(cue.textAlignment),
    )

    private fun unsetToNull(value: Float): Double? =
        if (value == Cue.DIMEN_UNSET) null else value.toDouble()

    private fun alignmentName(alignment: Layout.Alignment?): String? = when (alignment) {
        Layout.Alignment.ALIGN_NORMAL -> "start"
        Layout.Alignment.ALIGN_CENTER -> "center"
        Layout.Alignment.ALIGN_OPPOSITE -> "end"
        else -> null
    }

    /**
     * Slices [text] into non-overlapping runs, each with its own
     * resolved style. TtmlParser/SsaParser attach real StyleSpan,
     * UnderlineSpan, StrikethroughSpan, and Foreground/BackgroundColorSpan
     * instances — confirmed via the ExoPlayer 2.14 release notes ("added
     * support for bold, italic, underline, strikethrough, font size and
     * color in SSA subtitles"). An unstyled Cue just comes back as one run.
     */
    private fun extractRuns(text: CharSequence?): List<Map<String, Any?>> {
        if (text.isNullOrEmpty()) return emptyList()
        if (text !is Spanned) return listOf(mapOf("text" to text.toString()))

        // Every span start/end offset is a potential run boundary — the
        // set of active spans can only change at one of these points.
        val boundaries = sortedSetOf(0, text.length)
        for (span in text.getSpans(0, text.length, Any::class.java)) {
            boundaries.add(text.getSpanStart(span))
            boundaries.add(text.getSpanEnd(span))
        }
        val points = boundaries.toList()

        val runs = mutableListOf<Map<String, Any?>>()
        for (i in 0 until points.size - 1) {
            val start = points[i]
            val end = points[i + 1]
            if (start >= end) continue

            var bold = false
            var italic = false
            var underline = false
            var strikethrough = false
            var foregroundColor: Int? = null
            var backgroundColor: Int? = null

            for (span in text.getSpans(start, end, Any::class.java)) {
                when (span) {
                    is StyleSpan -> {
                        bold = bold || span.style == Typeface.BOLD || span.style == Typeface.BOLD_ITALIC
                        italic = italic || span.style == Typeface.ITALIC || span.style == Typeface.BOLD_ITALIC
                    }
                    is UnderlineSpan -> underline = true
                    is StrikethroughSpan -> strikethrough = true
                    is ForegroundColorSpan -> foregroundColor = span.foregroundColor
                    is BackgroundColorSpan -> backgroundColor = span.backgroundColor
                }
            }

            runs.add(
                mapOf(
                    "text" to text.subSequence(start, end).toString(),
                    "bold" to bold,
                    "italic" to italic,
                    "underline" to underline,
                    "strikethrough" to strikethrough,
                    "foregroundColor" to foregroundColor,
                    "backgroundColor" to backgroundColor,
                )
            )

            if (foregroundColor != null || backgroundColor != null) {
                Log.i(
                    TAG,
                    "Run \"${text.subSequence(start, end)}\" fg=${foregroundColor?.let { "#%08X".format(it) }} bg=${backgroundColor?.let { "#%08X".format(it) }}",
                )
            }
        }
        return runs
    }
}