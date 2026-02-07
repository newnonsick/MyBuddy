#include "main.h"

#include "src/whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "src/examples/dr_wav.h"

#include <cmath>
#include <fstream>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>
#include <mutex>
#include <atomic>
#include <iostream>
#include <chrono>
#include <cstring>
#include <cstdlib>
#include "json/json.hpp"
#include <stdio.h>

#ifdef __ANDROID__
#include <android/log.h>
#endif

using json = nlohmann::json;

static bool read_file_prefix(const std::string &path, char *out, size_t n)
{
    if (n == 0)
        return true;
    std::ifstream f(path, std::ios::binary);
    if (!f.good())
        return false;
    f.read(out, static_cast<std::streamsize>(n));
    return f.gcount() == static_cast<std::streamsize>(n);
}

static bool validate_model_file(const std::string &path, std::string &error)
{
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f.good())
    {
        error = "model file not found or not readable";
        return false;
    }
    const auto size = f.tellg();
    if (size < 0)
    {
        error = "failed to read model file size";
        return false;
    }
    // Most Whisper ggml/gguf models are many MB; tiny sanity floor prevents obvious wrong paths.
    if (size < static_cast<std::streamoff>(1024 * 1024))
    {
        error = "model file too small (likely invalid/corrupt)";
        return false;
    }

    char hdr4[4] = {0, 0, 0, 0};
    f.seekg(0, std::ios::beg);
    f.read(hdr4, 4);
    if (f.gcount() != 4)
    {
        error = "failed to read model file header";
        return false;
    }

    // Common wrong-file signatures that otherwise reach ggml and can hard-abort.
    const unsigned char b0 = static_cast<unsigned char>(hdr4[0]);
    const unsigned char b1 = static_cast<unsigned char>(hdr4[1]);
    if (hdr4[0] == 'P' && hdr4[1] == 'K')
    { // zip
        error = "model path points to a ZIP (did you forget to extract?)";
        return false;
    }
    if (b0 == 0x1F && b1 == 0x8B)
    { // gzip
        error = "model path points to a GZIP (unsupported; extract first)";
        return false;
    }
    if (hdr4[0] == '7' && hdr4[1] == 'z')
    { // 7z
        error = "model path points to a 7z archive (extract first)";
        return false;
    }
    if (hdr4[0] == 'R' && hdr4[1] == 'I' && hdr4[2] == 'F' && hdr4[3] == 'F')
    { // wav
        error = "model path points to a WAV file (wrong file selected)";
        return false;
    }
    if (hdr4[0] == 'O' && hdr4[1] == 'g' && hdr4[2] == 'g' && hdr4[3] == 'S')
    { // ogg
        error = "model path points to an OGG file (wrong file selected)";
        return false;
    }
    if (hdr4[0] == '<' || hdr4[0] == '{' || hdr4[0] == '[')
    {
        error = "model file looks like text/HTML/JSON (download may have failed)";
        return false;
    }

    // Don't hard-require ggml/gguf magic (some forks differ), but warn in logs.
    if (!((hdr4[0] == 'g' && hdr4[1] == 'g' && hdr4[2] == 'm' && hdr4[3] == 'l') ||
          (hdr4[0] == 'g' && hdr4[1] == 'g' && hdr4[2] == 'u' && hdr4[3] == 'f')))
    {
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_WARN, "WhisperFlutter",
                            "[WARN] Model header is not ggml/gguf (got: %02X %02X %02X %02X). Continuing.",
                            (int)b0, (int)b1, (int)static_cast<unsigned char>(hdr4[2]), (int)static_cast<unsigned char>(hdr4[3]));
#endif
    }

    return true;
}

static std::vector<float> resample_linear(const std::vector<float> &in, uint32_t in_sr, uint32_t out_sr)
{
    if (in_sr == 0 || out_sr == 0 || in.empty() || in_sr == out_sr)
    {
        return in;
    }
    const double ratio = static_cast<double>(out_sr) / static_cast<double>(in_sr);
    const size_t out_len = std::max<size_t>(1, static_cast<size_t>(std::llround(in.size() * ratio)));
    std::vector<float> out(out_len);

    for (size_t i = 0; i < out_len; i++)
    {
        const double src = static_cast<double>(i) / ratio;
        const size_t idx = static_cast<size_t>(src);
        const double frac = src - static_cast<double>(idx);

        const size_t idx0 = std::min(idx, in.size() - 1);
        const size_t idx1 = std::min(idx + 1, in.size() - 1);
        const float y0 = in[idx0];
        const float y1 = in[idx1];
        out[i] = static_cast<float>(y0 + (y1 - y0) * frac);
    }

    return out;
}

struct whisper_params
{
    int32_t seed = -1;
    int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());

    int32_t n_processors = 1;
    int32_t offset_t_ms = 0;
    int32_t offset_n = 0;
    int32_t duration_ms = 0;
    int32_t max_context = -1;
    int32_t max_len = 0;
    int32_t best_of = 5;
    int32_t beam_size = -1;

    float word_thold = 0.01f;
    float entropy_thold = 2.40f;
    float logprob_thold = -1.00f;

    bool verbose = false;
    bool print_special_tokens = false;
    bool speed_up = false;
    bool translate = false;
    bool diarize = false;
    bool no_fallback = false;
    bool output_txt = false;
    bool output_vtt = false;
    bool output_srt = false;
    bool output_wts = false;
    bool output_csv = false;
    bool print_special = false;
    bool print_colors = false;
    bool print_progress = false;
    bool no_timestamps = false;
    bool split_on_word = false;

    std::string language = "auto";
    std::string prompt;
    std::string model = "";
    std::string audio = "";
    std::vector<std::string> fname_inp = {};
    std::vector<std::string> fname_outp = {};
};

static struct whisper_context *g_ctx = nullptr;
static std::string g_model_path = "";
static std::mutex g_mutex;
static std::atomic<bool> g_should_abort(false);

static bool abort_callback(void *user_data)
{
    return g_should_abort.load();
}

static char *malloc_cstr(const std::string &s)
{
    // Allocate with libc malloc so we can free from native via free_response().
    char *out = static_cast<char *>(std::malloc(s.size() + 1));
    if (!out)
    {
        return nullptr;
    }
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

static char *jsonToMallocChar(const json &jsonData)
{
    try
    {
        // Ensure ASCII encoding to avoid UTF-8 issues across FFI boundary
        // Non-ASCII characters will be escaped as \uXXXX
        // Use 'replace' to handle malformed UTF-8 from Whisper output
        const std::string result = jsonData.dump(-1, ' ', true, nlohmann::json::error_handler_t::replace);
        char *ch = malloc_cstr(result);
        if (ch)
        {
            return ch;
        }
    }
    catch (...)
    {
    }

    // Fallback for absolute safety
    const std::string errorJson = "{\"@type\":\"error\",\"message\":\"JSON serialization failed\"}";
    return malloc_cstr(errorJson);
}

json transcribe(json jsonBody)
{
    std::lock_guard<std::mutex> lock(g_mutex);

    g_should_abort.store(false);

    whisper_params params;
    params.n_threads = jsonBody.value("threads", params.n_threads);
    params.verbose = jsonBody.value("is_verbose", false);
    params.translate = jsonBody.value("is_translate", false);
    params.language = jsonBody.value("language", params.language);
    params.print_special_tokens = jsonBody.value("is_special_tokens", false);
    params.no_timestamps = jsonBody.value("is_no_timestamps", false);
    params.model = jsonBody.value("model", std::string(""));
    params.audio = jsonBody.value("audio", std::string(""));
    params.split_on_word = jsonBody.value("split_on_word", false);
    params.diarize = jsonBody.value("diarize", false);
    params.speed_up = jsonBody.value("speed_up", false);

    // Clamp threads to a conservative range.
    const int32_t hw = std::max<int32_t>(1, (int32_t)std::thread::hardware_concurrency());
    const int32_t max_threads = std::min<int32_t>(4, hw);
    if (params.n_threads < 1)
        params.n_threads = 1;
    if (params.n_threads > max_threads)
        params.n_threads = max_threads;

    json jsonResult;
    jsonResult["@type"] = "transcribe";

    if (g_ctx == nullptr || g_model_path != params.model)
    {
        std::string model_error;
        if (!validate_model_file(params.model, model_error))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = std::string("invalid model file: ") + model_error;
            return jsonResult;
        }

        if (g_ctx != nullptr)
        {
            whisper_free(g_ctx);
            g_ctx = nullptr;
        }

        whisper_context_params cparams = whisper_context_default_params();
        // Be conservative on Android: GPU paths can abort on some devices.
        cparams.use_gpu = false;
        cparams.flash_attn = false;

        g_ctx = whisper_init_from_file_with_params(params.model.c_str(), cparams);
        if (g_ctx != nullptr)
        {
            g_model_path = params.model;
        }
    }

    if (g_ctx == nullptr)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to initialize whisper context (possibly OOM)";
        return jsonResult;
    }

    std::vector<float> pcmf32;
    uint32_t wav_sample_rate = 0;
    {
        drwav wav;
        if (!drwav_init_file(&wav, params.audio.c_str(), NULL))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = " failed to open WAV file ";
            return jsonResult;
        }

        wav_sample_rate = wav.sampleRate;
        if (wav_sample_rate == 0)
        {
            drwav_uninit(&wav);
            jsonResult["@type"] = "error";
            jsonResult["message"] = "invalid WAV sample rate";
            return jsonResult;
        }

        const uint32_t channels = wav.channels;
        if (channels == 0 || channels > 2)
        {
            drwav_uninit(&wav);
            jsonResult["@type"] = "error";
            jsonResult["message"] = "unsupported WAV channels";
            return jsonResult;
        }

        // dr_wav uses a 64-bit frame count; don't truncate to int.
        uint64_t n_frames = wav.totalPCMFrameCount;
        if (n_frames == 0)
        {
            // Some writers leave totalPCMFrameCount unset; derive from data chunk.
            const uint32_t bits = wav.bitsPerSample;
            const uint64_t bytesPerSample = bits / 8;
            if (bytesPerSample == 0)
            {
                drwav_uninit(&wav);
                jsonResult["@type"] = "error";
                jsonResult["message"] = "invalid WAV bitsPerSample";
                return jsonResult;
            }
            const uint64_t bytesPerFrame = bytesPerSample * channels;
            if (bytesPerFrame == 0)
            {
                drwav_uninit(&wav);
                jsonResult["@type"] = "error";
                jsonResult["message"] = "invalid WAV frame size";
                return jsonResult;
            }
            n_frames = wav.dataChunkDataSize / bytesPerFrame;
        }

        // Guard against corrupted headers producing absurd allocations.
        // Hold-to-record UX shouldn't create multi-minute files.
        const uint64_t max_frames = 16000ULL * 300ULL; // 5 minutes @16kHz
        if (n_frames == 0 || n_frames > max_frames)
        {
            drwav_uninit(&wav);
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV length out of bounds";
            return jsonResult;
        }

        const uint64_t sample_count = n_frames * static_cast<uint64_t>(channels);
        if (sample_count > (std::numeric_limits<size_t>::max)() / sizeof(int16_t))
        {
            drwav_uninit(&wav);
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV too large";
            return jsonResult;
        }

        std::vector<int16_t> pcm16(static_cast<size_t>(sample_count));
        const uint64_t read_frames = drwav_read_pcm_frames_s16(&wav, n_frames, pcm16.data());
        drwav_uninit(&wav);

        if (read_frames == 0)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "failed to read WAV frames";
            return jsonResult;
        }

        const uint64_t frames_to_use = std::min<uint64_t>(read_frames, n_frames);
        pcmf32.resize(static_cast<size_t>(frames_to_use));
        if (channels == 1)
        {
            for (uint64_t i = 0; i < frames_to_use; i++)
            {
                pcmf32[static_cast<size_t>(i)] = float(pcm16[static_cast<size_t>(i)]) / 32768.0f;
            }
        }
        else
        {
            for (uint64_t i = 0; i < frames_to_use; i++)
            {
                const size_t base = static_cast<size_t>(i * channels);
                const int32_t l = pcm16[base + 0];
                const int32_t r = pcm16[base + 1];
                pcmf32[static_cast<size_t>(i)] = float(l + r) / 65536.0f;
            }
        }
    }

    // Whisper expects 16kHz mono float PCM. If input isn't 16kHz, resample.
    if (wav_sample_rate != 16000)
    {
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_INFO, "WhisperFlutter",
                            "[INFO] Resampling audio %u Hz -> 16000 Hz (n=%zu)",
                            wav_sample_rate, pcmf32.size());
#endif
        pcmf32 = resample_linear(pcmf32, wav_sample_rate, 16000);
    }

    const int model_n_text_layer = whisper_model_n_text_layer(g_ctx);
    const int model_n_vocab = whisper_model_n_vocab(g_ctx);
    const bool is_turbo = (model_n_text_layer == 4 && model_n_vocab == 51866);

    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter",
                        "[DEBUG] Model info - n_text_layer: %d, n_vocab: %d, is_turbo: %d",
                        model_n_text_layer, model_n_vocab, is_turbo);

    whisper_sampling_strategy strategy = is_turbo ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY;
    whisper_full_params wparams = whisper_full_default_params(strategy);

    wparams.print_realtime = false;
    wparams.print_progress = false;
    wparams.print_timestamps = !params.no_timestamps;
    wparams.no_timestamps = params.no_timestamps;
    wparams.translate = params.translate;
    wparams.language = params.language.c_str();
    wparams.n_threads = params.n_threads;
    // Avoid experimental timestamp / DTW-related paths that can assert/abort on some builds.
    wparams.token_timestamps = false;
    wparams.max_len = 0;
    wparams.split_on_word = false;
    wparams.audio_ctx = params.speed_up ? 768 : 0; // Use smaller audio context for speedUp
    wparams.single_segment = false;
    wparams.vad = false;

    if (is_turbo)
    {
        wparams.beam_search.beam_size = 3;
        __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter",
                            "[DEBUG] Turbo model detected - using beam search (beam_size=3)");
    }

    // Intentionally not enabling split_on_word/token_timestamps.

    wparams.abort_callback = abort_callback;
    wparams.abort_callback_user_data = nullptr;

    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter",
                        "[DEBUG] Transcription params - threads: %d, speed_up: %d, no_timestamps: %d, single_segment: %d, split_on_word: %d, max_len: %d",
                        wparams.n_threads, params.speed_up, wparams.no_timestamps, wparams.single_segment, wparams.split_on_word, wparams.max_len);

    auto start_time = std::chrono::high_resolution_clock::now();

    if (whisper_full(g_ctx, wparams, pcmf32.data(), pcmf32.size()) != 0)
    {
        if (g_should_abort.load())
        {
            jsonResult["@type"] = "aborted";
            jsonResult["message"] = "transcription aborted by user";
            g_should_abort.store(false);
            return jsonResult;
        }
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to process audio";
        return jsonResult;
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter", "[DEBUG] Transcription completed in %lldms", (int)duration);

    const int n_segments = whisper_full_n_segments(g_ctx);
    std::vector<json> segmentsJson = {};
    std::string text_result = "";

    for (int i = 0; i < n_segments; ++i)
    {
        const char *text = whisper_full_get_segment_text(g_ctx, i);
        text_result += std::string(text);

        if (!params.no_timestamps)
        {
            json jsonSegment;
            jsonSegment["from_ts"] = whisper_full_get_segment_t0(g_ctx, i);
            jsonSegment["to_ts"] = whisper_full_get_segment_t1(g_ctx, i);
            jsonSegment["text"] = text;
            segmentsJson.push_back(jsonSegment);
        }
    }

    if (!params.no_timestamps)
    {
        jsonResult["segments"] = segmentsJson;
    }

    jsonResult["text"] = text_result;
    return jsonResult;
}

extern "C"
{
    FUNCTION_ATTRIBUTE char *request(char *body)
    {
        try
        {
            json jsonBody = json::parse(body);
            if (jsonBody["@type"] == "abort")
            {
                g_should_abort.store(true);
                return jsonToMallocChar({{"@type", "abort"}, {"message", "abort signal sent"}});
            }
            if (jsonBody["@type"] == "getTextFromWavFile")
            {
                return jsonToMallocChar(transcribe(jsonBody));
            }
            if (jsonBody["@type"] == "getVersion")
            {
                return jsonToMallocChar({{"@type", "version"}, {"message", "lib v1.8.3-accel"}});
            }
            return jsonToMallocChar({{"@type", "error"}, {"message", "method not found"}});
        }
        catch (const std::exception &e)
        {
            return jsonToMallocChar({{"@type", "error"}, {"message", e.what()}});
        }
    }

    FUNCTION_ATTRIBUTE void free_response(char *ptr)
    {
        if (ptr)
        {
            std::free(ptr);
        }
    }
}
