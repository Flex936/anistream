package com.anistream.app // TODO: replace with your actual applicationId package

import android.graphics.Typeface
import android.text.Layout
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import androidx.annotation.Nullable
import androidx.media3.common.text.Cue
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.SubtitleParser
import androidx.media3.extractor.text.ssa.SsaParser
import androidx.media3.extractor.text.ttml.TtmlParser
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

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
        "textSize" to unsetToNull(cue.textSize),
        "textSizeType" to textSizeTypeName(cue.textSize, cue.textSizeType),
    )

    private fun unsetToNull(value: Float): Double? =
        if (value == Cue.DIMEN_UNSET) null else value.toDouble()

    /**
     * Cue.textSizeType only means anything alongside an actual textSize
     * — unlike line/position, the type constant has no distinct "unset"
     * sentinel of its own, so this gates on the same DIMEN_UNSET check
     * unsetToNull() already applies to textSize itself.
     *
     * Confirmed directly against Cue.java: TEXT_SIZE_TYPE_FRACTIONAL=0,
     * TEXT_SIZE_TYPE_FRACTIONAL_IGNORE_PADDING=1, TEXT_SIZE_TYPE_ABSOLUTE=2.
     * SsaParser.createCue() specifically emits the IGNORE_PADDING variant
     * for a Style's Fontsize (confirmed by reading SsaParser.java) — both
     * fractional variants are treated identically here since
     * StyledSubtitleView has no separate padding concept to distinguish
     * them by; it measures directly against the full video bounds either
     * way, so both resolve to the same "fraction of the real video
     * height" formula on the Dart side.
     */
    private fun textSizeTypeName(textSize: Float, type: Int): String? {
        if (textSize == Cue.DIMEN_UNSET) return null
        return when (type) {
            Cue.TEXT_SIZE_TYPE_FRACTIONAL,
            Cue.TEXT_SIZE_TYPE_FRACTIONAL_IGNORE_PADDING -> "fractional"
            Cue.TEXT_SIZE_TYPE_ABSOLUTE -> "absolute"
            else -> null
        }
    }

    private fun alignmentName(alignment: Layout.Alignment?): String? = when (alignment) {
        Layout.Alignment.ALIGN_NORMAL -> "start"
        Layout.Alignment.ALIGN_CENTER -> "center"
        Layout.Alignment.ALIGN_OPPOSITE -> "end"
        else -> null
    }

    /**
     * Slices [text] into non-overlapping runs, each with its own
     * resolved per-run style. In practice, for SsaParser specifically,
     * every span here comes from the cue's single named Style, applied
     * uniformly across the whole cue (start=0 to end=length) — confirmed
     * by reading SsaParser.java's createCue() directly. Inline override
     * tags ({\b1}, {\c&H...&}, {\fs36}, etc.) are NOT read by SsaParser
     * at all: SsaStyle.Overrides.parseFromDialogue() only recognizes
     * \pos, \move, and \an — everything else inside a {...} block is
     * matched and silently discarded by the same regex that strips the
     * braces from the visible text. So a single SsaParser cue always
     * produces exactly one run today; the boundary-based splitting below
     * exists for TTML, whose per-node model can genuinely differ per
     * run (confirmed via TtmlRenderUtil.java), and stays a harmless
     * no-op against SsaParser's uniform whole-cue spans.
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