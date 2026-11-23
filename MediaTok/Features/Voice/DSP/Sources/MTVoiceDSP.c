#include "MTVoiceDSP.h"

#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// MARK: - Common pieces

#define MT_PI 3.14159265358979f
#define MT_SINE_TABLE_SIZE 2048
#define MT_BLOCK_FRAMES 1024
#define MT_CONTROL_INTERVAL 32
#define MT_MAX_CHANNELS 8

typedef struct MTBiquad {
    float b0;
    float b1;
    float b2;
    float a1;
    float a2;
    float z1;
    float z2;
} MTBiquad;

static inline float mt_biquad_run(MTBiquad *f, float x) {
    float y = f->b0 * x + f->z1;
    f->z1 = f->b1 * x - f->a1 * y + f->z2;
    f->z2 = f->b2 * x - f->a2 * y;
    return y;
}

static float mt_clamp_frequency(float frequency, float sampleRate) {
    float limit = sampleRate * 0.45f;
    if (frequency > limit) {
        return limit;
    }
    if (frequency < 10.0f) {
        return 10.0f;
    }
    return frequency;
}

static void mt_biquad_set(MTBiquad *f, float b0, float b1, float b2, float a0, float a1, float a2) {
    float inv = 1.0f / a0;
    f->b0 = b0 * inv;
    f->b1 = b1 * inv;
    f->b2 = b2 * inv;
    f->a1 = a1 * inv;
    f->a2 = a2 * inv;
}

static void mt_biquad_identity(MTBiquad *f) {
    f->b0 = 1.0f;
    f->b1 = 0.0f;
    f->b2 = 0.0f;
    f->a1 = 0.0f;
    f->a2 = 0.0f;
}

// Coefficient setters keep the state (z1, z2): a change of gain does not click.
static void mt_biquad_peak(MTBiquad *f, float sampleRate, float frequency, float q, float gainDb) {
    float A = powf(10.0f, gainDb / 40.0f);
    float w0 = 2.0f * MT_PI * mt_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) / (2.0f * q);
    mt_biquad_set(f, 1.0f + alpha * A, -2.0f * cosw, 1.0f - alpha * A, 1.0f + alpha / A, -2.0f * cosw, 1.0f - alpha / A);
}

static void mt_biquad_low_shelf(MTBiquad *f, float sampleRate, float frequency, float gainDb) {
    float A = powf(10.0f, gainDb / 40.0f);
    float w0 = 2.0f * MT_PI * mt_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) * 0.5f * 1.41421356f;
    float sqrtA2alpha = 2.0f * sqrtf(A) * alpha;
    mt_biquad_set(f,
        A * ((A + 1.0f) - (A - 1.0f) * cosw + sqrtA2alpha),
        2.0f * A * ((A - 1.0f) - (A + 1.0f) * cosw),
        A * ((A + 1.0f) - (A - 1.0f) * cosw - sqrtA2alpha),
        (A + 1.0f) + (A - 1.0f) * cosw + sqrtA2alpha,
        -2.0f * ((A - 1.0f) + (A + 1.0f) * cosw),
        (A + 1.0f) + (A - 1.0f) * cosw - sqrtA2alpha);
}

static void mt_biquad_high_shelf(MTBiquad *f, float sampleRate, float frequency, float gainDb) {
    float A = powf(10.0f, gainDb / 40.0f);
    float w0 = 2.0f * MT_PI * mt_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) * 0.5f * 1.41421356f;
    float sqrtA2alpha = 2.0f * sqrtf(A) * alpha;
    mt_biquad_set(f,
        A * ((A + 1.0f) + (A - 1.0f) * cosw + sqrtA2alpha),
        -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosw),
        A * ((A + 1.0f) + (A - 1.0f) * cosw - sqrtA2alpha),
        (A + 1.0f) - (A - 1.0f) * cosw + sqrtA2alpha,
        2.0f * ((A - 1.0f) - (A + 1.0f) * cosw),
        (A + 1.0f) - (A - 1.0f) * cosw - sqrtA2alpha);
}

static void mt_biquad_high_pass(MTBiquad *f, float sampleRate, float frequency) {
    float w0 = 2.0f * MT_PI * mt_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) / (2.0f * 0.7071f);
    mt_biquad_set(f, (1.0f + cosw) * 0.5f, -(1.0f + cosw), (1.0f + cosw) * 0.5f, 1.0f + alpha, -2.0f * cosw, 1.0f - alpha);
}

static void mt_biquad_low_pass(MTBiquad *f, float sampleRate, float frequency) {
    float w0 = 2.0f * MT_PI * mt_clamp_frequency(frequency, sampleRate) / sampleRate;
    float cosw = cosf(w0);
    float alpha = sinf(w0) / (2.0f * 0.7071f);
    mt_biquad_set(f, (1.0f - cosw) * 0.5f, 1.0f - cosw, (1.0f - cosw) * 0.5f, 1.0f + alpha, -2.0f * cosw, 1.0f - alpha);
}

static inline float mt_fast_tanh(float x) {
    if (x > 3.0f) {
        return 1.0f;
    }
    if (x < -3.0f) {
        return -1.0f;
    }
    float x2 = x * x;
    return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

static inline float mt_soft_limit(float x) {
    float a = fabsf(x);
    if (a <= 0.8f) {
        return x;
    }
    float limited = 0.8f + 0.2f * mt_fast_tanh((a - 0.8f) / 0.2f);
    return x < 0.0f ? -limited : limited;
}

static inline int16_t mt_float_to_int16(float x) {
    float scaled = x * 32767.0f;
    if (scaled > 32767.0f) {
        return 32767;
    }
    if (scaled < -32768.0f) {
        return -32768;
    }
    return (int16_t)lrintf(scaled);
}

static uint32_t mt_next_power_of_two(uint32_t value) {
    uint32_t result = 1;
    while (result < value && result < (1u << 30)) {
        result <<= 1;
    }
    return result;
}

static float mt_clampf(float value, float minValue, float maxValue) {
    if (!(value == value)) {
        return minValue;
    }
    if (value < minValue) {
        return minValue;
    }
    if (value > maxValue) {
        return maxValue;
    }
    return value;
}

// MARK: - Voice parameters

void MTVoiceParamsSetIdentity(MTVoiceParams *params) {
    memset(params, 0, sizeof(MTVoiceParams));
    params->bitcrushBits = 16.0f;
    params->echoDelayMs = 250.0f;
    params->reverbSize = 0.5f;
    params->wet = 1.0f;
}

static MTVoiceParams mt_sanitized_params(const MTVoiceParams *source) {
    MTVoiceParams p = *source;
    p.pitchSemitones = mt_clampf(p.pitchSemitones, -12.0f, 12.0f);
    p.timbre = mt_clampf(p.timbre, -1.0f, 1.0f);
    p.bassDb = mt_clampf(p.bassDb, -12.0f, 12.0f);
    p.midDb = mt_clampf(p.midDb, -12.0f, 12.0f);
    p.trebleDb = mt_clampf(p.trebleDb, -12.0f, 12.0f);
    p.telephone = mt_clampf(p.telephone, 0.0f, 1.0f);
    p.distortion = mt_clampf(p.distortion, 0.0f, 1.0f);
    p.bitcrushBits = mt_clampf(p.bitcrushBits, 2.0f, 16.0f);
    p.ringModHz = mt_clampf(p.ringModHz, 0.0f, 1000.0f);
    p.ringModMix = mt_clampf(p.ringModMix, 0.0f, 1.0f);
    p.chorus = mt_clampf(p.chorus, 0.0f, 1.0f);
    p.flanger = mt_clampf(p.flanger, 0.0f, 1.0f);
    p.echoMix = mt_clampf(p.echoMix, 0.0f, 1.0f);
    p.echoDelayMs = mt_clampf(p.echoDelayMs, 40.0f, 800.0f);
    p.echoFeedback = mt_clampf(p.echoFeedback, 0.0f, 0.8f);
    p.reverbMix = mt_clampf(p.reverbMix, 0.0f, 1.0f);
    p.reverbSize = mt_clampf(p.reverbSize, 0.0f, 1.0f);
    p.breathiness = mt_clampf(p.breathiness, 0.0f, 1.0f);
    p.compression = mt_clampf(p.compression, 0.0f, 1.0f);
    p.gainDb = mt_clampf(p.gainDb, -12.0f, 12.0f);
    p.vibratoRateHz = mt_clampf(p.vibratoRateHz, 0.0f, 12.0f);
    p.vibratoDepth = mt_clampf(p.vibratoDepth, 0.0f, 1.0f);
    p.jitter = mt_clampf(p.jitter, 0.0f, 1.0f);
    p.wet = mt_clampf(p.wet, 0.0f, 1.0f);
    return p;
}

static bool mt_pitch_active(const MTVoiceParams *p) {
    if (fabsf(p->pitchSemitones) > 0.01f) {
        return true;
    }
    if (p->vibratoDepth > 0.001f && p->vibratoRateHz > 0.01f) {
        return true;
    }
    return p->jitter > 0.001f;
}

bool MTVoiceParamsIsIdentity(const MTVoiceParams *source) {
    MTVoiceParams p = mt_sanitized_params(source);
    if (p.wet < 0.001f) {
        return fabsf(p.gainDb) < 0.01f;
    }
    if (mt_pitch_active(&p)) {
        return false;
    }
    if (fabsf(p.timbre) > 0.01f || fabsf(p.bassDb) > 0.01f || fabsf(p.midDb) > 0.01f || fabsf(p.trebleDb) > 0.01f) {
        return false;
    }
    if (p.telephone > 0.001f || p.distortion > 0.001f || p.bitcrushBits < 15.99f) {
        return false;
    }
    if (p.ringModHz > 0.01f && p.ringModMix > 0.001f) {
        return false;
    }
    if (p.chorus > 0.001f || p.flanger > 0.001f || p.echoMix > 0.001f || p.reverbMix > 0.001f) {
        return false;
    }
    if (p.breathiness > 0.001f || p.compression > 0.001f || fabsf(p.gainDb) > 0.01f) {
        return false;
    }
    return true;
}

// MARK: - Voice chain

struct MTVoiceChain {
    MTVoiceParams params;
    uint32_t maxSampleRate;
    uint32_t sampleRate;
    float sineTable[MT_SINE_TABLE_SIZE + 1];
    float scratch[MT_BLOCK_FRAMES];
    uint32_t rng;

    // Pitch: two crossfaded taps on one delay line (WSOLA pitch-synchronized).
    bool pitchActive;
    float *pitchBuffer;
    uint32_t pitchMask;
    uint32_t pitchWrite;
    float pitchWindow;
    float pitchPhase;
    float pitchRatio;
    float pitchOffset1;
    float pitchOffset2;
    MTBiquad pitchRumbleHP;
    bool pitchRumbleActive;
    uint32_t controlCounter;
    float vibratoPhase;
    float vibratoIncrement;
    float jitterValue;
    float jitterTarget;
    uint32_t jitterCounter;
    uint32_t jitterPeriod;

    // Filters.
    bool timbreActive;
    MTBiquad timbreLow;
    MTBiquad timbreHigh;
    bool eqActive;
    MTBiquad eqLow;
    MTBiquad eqMid;
    MTBiquad eqHigh;
    bool phoneActive;
    MTBiquad phoneHigh;
    MTBiquad phoneLow;

    // Distortion and bitcrusher.
    float distortionDrive;
    float distortionNorm;
    float bitcrushLevels;

    // Ring modulator.
    bool ringActive;
    float ringPhase;
    float ringIncrement;

    // Chorus.
    float *chorusBuffer;
    uint32_t chorusMask;
    uint32_t chorusWrite;
    float chorusPhase;
    float chorusIncrement;
    float chorusBase;
    float chorusDepth;

    // Flanger.
    float *flangerBuffer;
    uint32_t flangerMask;
    uint32_t flangerWrite;
    float flangerPhase;
    float flangerIncrement;
    float flangerBase;
    float flangerDepth;

    // Echo.
    float *echoBuffer;
    uint32_t echoMask;
    uint32_t echoWrite;
    uint32_t echoDelay;

    // Reverb (4 damped combs + 2 allpasses).
    float *combBuffers[4];
    uint32_t combCapacity[4];
    uint32_t combLength[4];
    uint32_t combIndex[4];
    float combStore[4];
    float combFeedback;
    float combDamp;
    float *allpassBuffers[2];
    uint32_t allpassCapacity[2];
    uint32_t allpassLength[2];
    uint32_t allpassIndex[2];

    // Breath.
    float breathEnvelope;
    float breathRelease;
    float breathHighPass;
    float breathPreviousNoise;
    float breathCoefficient;

    // Compressor.
    bool compressorActive;
    float compressorEnvelope;
    float compressorGain;
    float compressorTargetGain;
    float compressorThresholdDb;
    float compressorRatio;
    float compressorAttack;
    float compressorRelease;
    float compressorMakeupDb;
    uint32_t compressorCounter;

    float gainLinear;
};

static const float mt_comb_tuning[4] = { 1116.0f, 1188.0f, 1277.0f, 1356.0f };
static const float mt_allpass_tuning[2] = { 556.0f, 441.0f };

static inline float mt_chain_sine(const MTVoiceChain *chain, float phase) {
    float position = phase * (float)MT_SINE_TABLE_SIZE;
    int index = (int)position;
    if (index < 0) {
        index = 0;
    }
    if (index >= MT_SINE_TABLE_SIZE) {
        index = MT_SINE_TABLE_SIZE - 1;
    }
    float frac = position - (float)index;
    return chain->sineTable[index] + frac * (chain->sineTable[index + 1] - chain->sineTable[index]);
}

static inline float mt_wrap_phase(float phase) {
    if (phase >= 1.0f) {
        phase -= floorf(phase);
    } else if (phase < 0.0f) {
        phase -= floorf(phase);
    }
    return phase;
}

static inline uint32_t mt_next_random(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

static inline float mt_random_bipolar(uint32_t *state) {
    return (float)(mt_next_random(state) >> 8) * (1.0f / 8388608.0f) - 1.0f;
}

static inline float mt_delay_read(const float *buffer, uint32_t mask, uint32_t writeIndex, float delay) {
    float position = (float)writeIndex - 1.0f - delay;
    float size = (float)(mask + 1);
    while (position < 0.0f) {
        position += size;
    }
    uint32_t i0 = ((uint32_t)position) & mask;
    float frac = position - floorf(position);
    uint32_t i1 = (i0 + 1) & mask;
    return buffer[i0] + frac * (buffer[i1] - buffer[i0]);
}

static float *mt_alloc_buffer(uint32_t count) {
    return (float *)calloc(count, sizeof(float));
}

MTVoiceChain *MTVoiceChainCreate(const MTVoiceParams *params, uint32_t maxSampleRate) {
    MTVoiceChain *chain = (MTVoiceChain *)calloc(1, sizeof(MTVoiceChain));
    if (chain == NULL) {
        return NULL;
    }
    chain->params = mt_sanitized_params(params);
    if (maxSampleRate < 8000) {
        maxSampleRate = 8000;
    }
    if (maxSampleRate > 96000) {
        maxSampleRate = 96000;
    }
    chain->maxSampleRate = maxSampleRate;
    chain->rng = 0x9E3779B9u ^ (uint32_t)(uintptr_t)chain;
    if (chain->rng == 0) {
        chain->rng = 1;
    }
    for (int i = 0; i <= MT_SINE_TABLE_SIZE; i++) {
        chain->sineTable[i] = sinf(2.0f * MT_PI * (float)i / (float)MT_SINE_TABLE_SIZE);
    }

    const MTVoiceParams *p = &chain->params;
    float maxRate = (float)maxSampleRate;
    bool failed = false;

    chain->pitchActive = mt_pitch_active(p);
    if (chain->pitchActive) {
        uint32_t size = mt_next_power_of_two((uint32_t)(maxRate * 0.25f));
        chain->pitchBuffer = mt_alloc_buffer(size);
        chain->pitchMask = size - 1;
        failed = failed || chain->pitchBuffer == NULL;
    }
    if (p->chorus > 0.001f) {
        uint32_t size = mt_next_power_of_two((uint32_t)(maxRate * 0.04f));
        chain->chorusBuffer = mt_alloc_buffer(size);
        chain->chorusMask = size - 1;
        failed = failed || chain->chorusBuffer == NULL;
    }
    if (p->flanger > 0.001f) {
        uint32_t size = mt_next_power_of_two((uint32_t)(maxRate * 0.012f));
        chain->flangerBuffer = mt_alloc_buffer(size);
        chain->flangerMask = size - 1;
        failed = failed || chain->flangerBuffer == NULL;
    }
    if (p->echoMix > 0.001f) {
        uint32_t size = mt_next_power_of_two((uint32_t)(maxRate * 0.82f));
        chain->echoBuffer = mt_alloc_buffer(size);
        chain->echoMask = size - 1;
        failed = failed || chain->echoBuffer == NULL;
    }
    if (p->reverbMix > 0.001f) {
        for (int i = 0; i < 4; i++) {
            uint32_t capacity = (uint32_t)(mt_comb_tuning[i] * maxRate / 44100.0f * 1.35f) + 2;
            chain->combBuffers[i] = mt_alloc_buffer(capacity);
            chain->combCapacity[i] = capacity;
            failed = failed || chain->combBuffers[i] == NULL;
        }
        for (int i = 0; i < 2; i++) {
            uint32_t capacity = (uint32_t)(mt_allpass_tuning[i] * maxRate / 44100.0f) + 2;
            chain->allpassBuffers[i] = mt_alloc_buffer(capacity);
            chain->allpassCapacity[i] = capacity;
            failed = failed || chain->allpassBuffers[i] == NULL;
        }
    }
    if (failed) {
        MTVoiceChainDestroy(chain);
        return NULL;
    }
    return chain;
}

void MTVoiceChainDestroy(MTVoiceChain *chain) {
    if (chain == NULL) {
        return;
    }
    free(chain->pitchBuffer);
    free(chain->chorusBuffer);
    free(chain->flangerBuffer);
    free(chain->echoBuffer);
    for (int i = 0; i < 4; i++) {
        free(chain->combBuffers[i]);
    }
    for (int i = 0; i < 2; i++) {
        free(chain->allpassBuffers[i]);
    }
    free(chain);
}

static void mt_clear_biquad(MTBiquad *f) {
    f->z1 = 0.0f;
    f->z2 = 0.0f;
}

void MTVoiceChainReset(MTVoiceChain *chain) {
    if (chain->pitchBuffer != NULL) {
        memset(chain->pitchBuffer, 0, sizeof(float) * (chain->pitchMask + 1));
    }
    if (chain->chorusBuffer != NULL) {
        memset(chain->chorusBuffer, 0, sizeof(float) * (chain->chorusMask + 1));
    }
    if (chain->flangerBuffer != NULL) {
        memset(chain->flangerBuffer, 0, sizeof(float) * (chain->flangerMask + 1));
    }
    if (chain->echoBuffer != NULL) {
        memset(chain->echoBuffer, 0, sizeof(float) * (chain->echoMask + 1));
    }
    for (int i = 0; i < 4; i++) {
        if (chain->combBuffers[i] != NULL) {
            memset(chain->combBuffers[i], 0, sizeof(float) * chain->combCapacity[i]);
        }
        chain->combIndex[i] = 0;
        chain->combStore[i] = 0.0f;
    }
    for (int i = 0; i < 2; i++) {
        if (chain->allpassBuffers[i] != NULL) {
            memset(chain->allpassBuffers[i], 0, sizeof(float) * chain->allpassCapacity[i]);
        }
        chain->allpassIndex[i] = 0;
    }
    mt_clear_biquad(&chain->pitchRumbleHP);
    mt_clear_biquad(&chain->timbreLow);
    mt_clear_biquad(&chain->timbreHigh);
    mt_clear_biquad(&chain->eqLow);
    mt_clear_biquad(&chain->eqMid);
    mt_clear_biquad(&chain->eqHigh);
    mt_clear_biquad(&chain->phoneHigh);
    mt_clear_biquad(&chain->phoneLow);
    chain->pitchWrite = 0;
    chain->pitchPhase = 0.0f;
    chain->pitchOffset1 = 0.0f;
    chain->pitchOffset2 = 0.0f;
    chain->controlCounter = 0;
    chain->vibratoPhase = 0.0f;
    chain->jitterValue = 0.0f;
    chain->jitterTarget = 0.0f;
    chain->jitterCounter = 0;
    chain->ringPhase = 0.0f;
    chain->chorusWrite = 0;
    chain->chorusPhase = 0.0f;
    chain->flangerWrite = 0;
    chain->flangerPhase = 0.0f;
    chain->echoWrite = 0;
    chain->breathEnvelope = 0.0f;
    chain->breathHighPass = 0.0f;
    chain->breathPreviousNoise = 0.0f;
    chain->compressorEnvelope = 0.0f;
    chain->compressorGain = 1.0f;
    chain->compressorTargetGain = 1.0f;
    chain->compressorCounter = 0;
}

/// Everything that depends on the sample rate. Math only, no allocation: callable on the realtime thread.
static void mt_chain_configure(MTVoiceChain *chain, uint32_t sampleRate) {
    const MTVoiceParams *p = &chain->params;
    float rate = (float)sampleRate;
    chain->sampleRate = sampleRate;

    if (chain->pitchActive) {
        float window = (p->pitchSemitones < -0.1f) ? (rate * 0.072f) : (rate * 0.050f);
        int maxSearch = (int)(rate * 0.013f);
        int corrLen = (int)(rate * 0.010f);
        float guardSamples = (float)(2 * maxSearch + corrLen + 16);
        float limit = (float)chain->pitchMask - guardSamples;
        if (window > limit) {
            window = limit;
        }
        if (window < 64.0f) {
            window = 64.0f;
        }
        chain->pitchWindow = window;
        chain->pitchRatio = powf(2.0f, p->pitchSemitones / 12.0f);
        chain->pitchRumbleActive = p->pitchSemitones < -0.5f;
        if (chain->pitchRumbleActive) {
            mt_biquad_high_pass(&chain->pitchRumbleHP, rate, 72.0f);
        } else {
            mt_biquad_identity(&chain->pitchRumbleHP);
        }
        chain->vibratoIncrement = p->vibratoRateHz * (float)MT_CONTROL_INTERVAL / rate;
        chain->jitterPeriod = (uint32_t)(rate * 0.15f / (float)MT_CONTROL_INTERVAL) + 1;
    } else {
        chain->pitchRumbleActive = false;
    }

    chain->timbreActive = fabsf(p->timbre) > 0.01f;
    if (chain->timbreActive) {
        mt_biquad_low_shelf(&chain->timbreLow, rate, 300.0f, -6.0f * p->timbre);
        mt_biquad_high_shelf(&chain->timbreHigh, rate, 2500.0f, 9.0f * p->timbre);
    }
    chain->eqActive = fabsf(p->bassDb) > 0.01f || fabsf(p->midDb) > 0.01f || fabsf(p->trebleDb) > 0.01f;
    if (chain->eqActive) {
        mt_biquad_low_shelf(&chain->eqLow, rate, 200.0f, p->bassDb);
        mt_biquad_peak(&chain->eqMid, rate, 1000.0f, 0.8f, p->midDb);
        mt_biquad_high_shelf(&chain->eqHigh, rate, 4000.0f, p->trebleDb);
    }
    chain->phoneActive = p->telephone > 0.001f;
    if (chain->phoneActive) {
        mt_biquad_high_pass(&chain->phoneHigh, rate, 300.0f);
        mt_biquad_low_pass(&chain->phoneLow, rate, 3400.0f);
    }

    chain->distortionDrive = 1.0f + 14.0f * p->distortion;
    chain->distortionNorm = 1.0f / mt_fast_tanh(chain->distortionDrive);
    chain->bitcrushLevels = powf(2.0f, p->bitcrushBits - 1.0f);

    chain->ringActive = p->ringModHz > 0.01f && p->ringModMix > 0.001f;
    chain->ringIncrement = p->ringModHz / rate;

    if (chain->chorusBuffer != NULL) {
        chain->chorusIncrement = 0.8f / rate;
        chain->chorusBase = rate * 0.02f;
        chain->chorusDepth = rate * 0.005f;
        float limit = (float)chain->chorusMask - 2.0f;
        if (chain->chorusBase + chain->chorusDepth > limit) {
            chain->chorusBase = limit * 0.7f;
            chain->chorusDepth = limit * 0.25f;
        }
    }
    if (chain->flangerBuffer != NULL) {
        chain->flangerIncrement = 0.25f / rate;
        chain->flangerBase = rate * 0.0035f;
        chain->flangerDepth = rate * 0.0025f;
        float limit = (float)chain->flangerMask - 2.0f;
        if (chain->flangerBase + chain->flangerDepth > limit) {
            chain->flangerBase = limit * 0.55f;
            chain->flangerDepth = limit * 0.4f;
        }
    }
    if (chain->echoBuffer != NULL) {
        uint32_t delay = (uint32_t)(p->echoDelayMs * 0.001f * rate);
        if (delay > chain->echoMask) {
            delay = chain->echoMask;
        }
        if (delay < 1) {
            delay = 1;
        }
        chain->echoDelay = delay;
    }
    if (chain->combBuffers[0] != NULL) {
        float sizeScale = 0.75f + 0.5f * p->reverbSize;
        for (int i = 0; i < 4; i++) {
            uint32_t length = (uint32_t)(mt_comb_tuning[i] * rate / 44100.0f * sizeScale);
            if (length >= chain->combCapacity[i]) {
                length = chain->combCapacity[i] - 1;
            }
            if (length < 1) {
                length = 1;
            }
            chain->combLength[i] = length;
            chain->combIndex[i] = 0;
        }
        for (int i = 0; i < 2; i++) {
            uint32_t length = (uint32_t)(mt_allpass_tuning[i] * rate / 44100.0f);
            if (length >= chain->allpassCapacity[i]) {
                length = chain->allpassCapacity[i] - 1;
            }
            if (length < 1) {
                length = 1;
            }
            chain->allpassLength[i] = length;
            chain->allpassIndex[i] = 0;
        }
        chain->combFeedback = 0.70f + 0.25f * p->reverbSize;
        chain->combDamp = 0.3f;
    }

    chain->breathRelease = expf(-1.0f / (0.03f * rate));
    chain->breathCoefficient = expf(-2.0f * MT_PI * 2000.0f / rate);

    chain->compressorActive = p->compression > 0.001f;
    if (chain->compressorActive) {
        chain->compressorThresholdDb = -8.0f - 22.0f * p->compression;
        chain->compressorRatio = 1.0f + 5.0f * p->compression;
        chain->compressorAttack = 1.0f - expf(-1.0f / (0.005f * rate));
        chain->compressorRelease = 1.0f - expf(-1.0f / (0.08f * rate));
        chain->compressorMakeupDb = -chain->compressorThresholdDb * (1.0f - 1.0f / chain->compressorRatio) * 0.5f;
    }
    chain->gainLinear = powf(10.0f, p->gainDb / 20.0f);

    MTVoiceChainReset(chain);
}

static void mt_chain_update_pitch_control(MTVoiceChain *chain) {
    const MTVoiceParams *p = &chain->params;
    float semitones = p->pitchSemitones;
    if (p->vibratoDepth > 0.001f && p->vibratoRateHz > 0.01f) {
        chain->vibratoPhase = mt_wrap_phase(chain->vibratoPhase + chain->vibratoIncrement);
        semitones += p->vibratoDepth * mt_chain_sine(chain, chain->vibratoPhase);
    }
    if (p->jitter > 0.001f) {
        chain->jitterCounter += 1;
        if (chain->jitterCounter >= chain->jitterPeriod) {
            chain->jitterCounter = 0;
            chain->jitterTarget = mt_random_bipolar(&chain->rng) * 0.7f * p->jitter;
        }
        chain->jitterValue += (chain->jitterTarget - chain->jitterValue) * 0.08f;
        semitones += chain->jitterValue;
    }
    chain->pitchRatio = exp2f(semitones / 12.0f);
}

static float mt_wsola_find_offset(
    const float *buffer,
    uint32_t mask,
    uint32_t writeIndex,
    float activeDelay,
    float baseDelay,
    int maxSearch,
    int corrLen,
    float minAllowedDelay,
    float maxAllowedDelay
) {
    if (maxSearch < 2 || corrLen < 4) {
        return 0.0f;
    }
    if (activeDelay < minAllowedDelay || activeDelay > maxAllowedDelay) {
        return 0.0f;
    }
    int activeDelayInt = (int)lrintf(activeDelay);
    uint32_t refBase = (writeIndex - 1u - (uint32_t)activeDelayInt) & mask;

    // Quick energy check on active tap so silence skips correlation work cleanly.
    float refEnergy = 0.0f;
    for (int k = 0; k < corrLen; k += 2) {
        float r = buffer[(refBase - (uint32_t)k) & mask];
        refEnergy += r * r;
    }
    if (refEnergy < 1e-8f) {
        return 0.0f;
    }

    float bestScore = -1e30f;
    int bestDelta = 0;
    for (int delta = -maxSearch; delta <= maxSearch; delta += 2) {
        float candDelay = baseDelay + (float)delta;
        if (candDelay < minAllowedDelay || candDelay > maxAllowedDelay) {
            continue;
        }
        int candDelayInt = (int)lrintf(candDelay);
        uint32_t candBase = (writeIndex - 1u - (uint32_t)candDelayInt) & mask;
        float dot = 0.0f;
        float candEnergy = 1e-9f;
        for (int k = 0; k < corrLen; k += 2) {
            float r = buffer[(refBase - (uint32_t)k) & mask];
            float c = buffer[(candBase - (uint32_t)k) & mask];
            dot += r * c;
            candEnergy += c * c;
        }
        float score = dot / sqrtf(candEnergy);
        if (score > bestScore) {
            bestScore = score;
            bestDelta = delta;
        }
    }
    return (float)bestDelta;
}

static inline float mt_chain_pitch(MTVoiceChain *chain, float x) {
    float *buffer = chain->pitchBuffer;
    uint32_t mask = chain->pitchMask;
    buffer[chain->pitchWrite] = x;
    chain->pitchWrite = (chain->pitchWrite + 1) & mask;

    float window = chain->pitchWindow;
    float rate = (float)(chain->sampleRate > 0 ? chain->sampleRate : 48000u);
    int maxSearch = (int)(rate * 0.013f);
    int corrLen = (int)(rate * 0.010f);
    int maxPossibleSearch = ((int)mask - corrLen - 16) / 3;
    if (maxPossibleSearch < 0) {
        maxPossibleSearch = 0;
    }
    if (maxSearch > maxPossibleSearch) {
        maxSearch = maxPossibleSearch;
    }
    float margin = (float)(maxSearch + 4);
    float maxDelayLimit = (float)((int)mask - corrLen - 4);
    if (maxDelayLimit < 2.0f) {
        maxDelayLimit = 2.0f;
    }

    float prevPhase = chain->pitchPhase;
    float prevPhase2 = prevPhase + 0.5f;
    if (prevPhase2 >= 1.0f) {
        prevPhase2 -= 1.0f;
    }

    float step = (1.0f - chain->pitchRatio) / window;
    float rawPhase = prevPhase + step;
    float phase = mt_wrap_phase(rawPhase);
    chain->pitchPhase = phase;

    float phase2 = phase + 0.5f;
    if (phase2 >= 1.0f) {
        phase2 -= 1.0f;
    }

    bool wrapped1 = (step >= 0.0f) ? (phase < prevPhase) : (rawPhase < 0.0f && phase > prevPhase);
    bool wrapped2 = (step >= 0.0f) ? (phase2 < prevPhase2) : (prevPhase >= 0.5f && phase < 0.5f && (prevPhase - phase) < 0.5f);

    if (wrapped1) {
        float activeDelay2 = margin + phase2 * window + chain->pitchOffset2;
        float baseDelay1 = margin + phase * window;
        chain->pitchOffset1 = mt_wsola_find_offset(
            buffer,
            mask,
            chain->pitchWrite,
            activeDelay2,
            baseDelay1,
            maxSearch,
            corrLen,
            1.0f,
            maxDelayLimit
        );
    }
    if (wrapped2) {
        float activeDelay1 = margin + phase * window + chain->pitchOffset1;
        float baseDelay2 = margin + phase2 * window;
        chain->pitchOffset2 = mt_wsola_find_offset(
            buffer,
            mask,
            chain->pitchWrite,
            activeDelay1,
            baseDelay2,
            maxSearch,
            corrLen,
            1.0f,
            maxDelayLimit
        );
    }

    // sin²(πp) + sin²(π(p + ½)) = 1: the taps fade out to 0.0 exactly where their delay wraps.
    float s1 = mt_chain_sine(chain, phase * 0.5f);
    float s2 = mt_chain_sine(chain, phase2 * 0.5f);
    float g1 = s1 * s1;
    float g2 = s2 * s2;

    float d1 = mt_clampf(margin + phase * window + chain->pitchOffset1, 1.0f, maxDelayLimit);
    float d2 = mt_clampf(margin + phase2 * window + chain->pitchOffset2, 1.0f, maxDelayLimit);

    float y1 = mt_delay_read(buffer, mask, chain->pitchWrite, d1);
    float y2 = mt_delay_read(buffer, mask, chain->pitchWrite, d2);
    float out = y1 * g1 + y2 * g2;
    if (chain->pitchRumbleActive) {
        out = mt_biquad_run(&chain->pitchRumbleHP, out);
    }
    return out;
}

static void mt_chain_process_mono(MTVoiceChain *chain, float *samples, size_t frames) {
    const MTVoiceParams *p = &chain->params;
    for (size_t i = 0; i < frames; i++) {
        float dry = samples[i];
        float x = dry;

        if (chain->pitchActive) {
            if (chain->controlCounter == 0) {
                mt_chain_update_pitch_control(chain);
            }
            chain->controlCounter = (chain->controlCounter + 1) % MT_CONTROL_INTERVAL;
            x = mt_chain_pitch(chain, x);
        }
        if (chain->timbreActive) {
            x = mt_biquad_run(&chain->timbreHigh, mt_biquad_run(&chain->timbreLow, x));
        }
        if (chain->eqActive) {
            x = mt_biquad_run(&chain->eqHigh, mt_biquad_run(&chain->eqMid, mt_biquad_run(&chain->eqLow, x)));
        }
        if (chain->phoneActive) {
            float band = mt_biquad_run(&chain->phoneLow, mt_biquad_run(&chain->phoneHigh, x));
            x = x + (band * 1.4f - x) * p->telephone;
        }
        if (p->distortion > 0.001f) {
            float saturated = mt_fast_tanh(x * chain->distortionDrive) * chain->distortionNorm;
            x = x + (saturated - x) * p->distortion;
        }
        if (p->bitcrushBits < 15.99f) {
            x = floorf(x * chain->bitcrushLevels + 0.5f) / chain->bitcrushLevels;
        }
        if (chain->ringActive) {
            chain->ringPhase = mt_wrap_phase(chain->ringPhase + chain->ringIncrement);
            float modulated = x * mt_chain_sine(chain, chain->ringPhase);
            x = x + (modulated - x) * p->ringModMix;
        }
        if (chain->chorusBuffer != NULL) {
            chain->chorusBuffer[chain->chorusWrite] = x;
            chain->chorusWrite = (chain->chorusWrite + 1) & chain->chorusMask;
            chain->chorusPhase = mt_wrap_phase(chain->chorusPhase + chain->chorusIncrement);
            float delay = chain->chorusBase + chain->chorusDepth * mt_chain_sine(chain, chain->chorusPhase);
            float delayed = mt_delay_read(chain->chorusBuffer, chain->chorusMask, chain->chorusWrite, delay);
            x = x * (1.0f - 0.4f * p->chorus) + delayed * 0.6f * p->chorus;
        }
        if (chain->flangerBuffer != NULL) {
            chain->flangerPhase = mt_wrap_phase(chain->flangerPhase + chain->flangerIncrement);
            float delay = chain->flangerBase + chain->flangerDepth * mt_chain_sine(chain, chain->flangerPhase);
            float delayed = mt_delay_read(chain->flangerBuffer, chain->flangerMask, chain->flangerWrite, delay);
            chain->flangerBuffer[chain->flangerWrite] = x + delayed * 0.55f * p->flanger;
            chain->flangerWrite = (chain->flangerWrite + 1) & chain->flangerMask;
            x = (x + delayed * p->flanger) / (1.0f + 0.5f * p->flanger);
        }
        if (chain->echoBuffer != NULL) {
            uint32_t readIndex = (chain->echoWrite - chain->echoDelay) & chain->echoMask;
            float delayed = chain->echoBuffer[readIndex];
            chain->echoBuffer[chain->echoWrite] = x + delayed * p->echoFeedback;
            chain->echoWrite = (chain->echoWrite + 1) & chain->echoMask;
            x = x + delayed * p->echoMix;
        }
        if (chain->combBuffers[0] != NULL) {
            float input = x * 0.3f;
            float sum = 0.0f;
            for (int c = 0; c < 4; c++) {
                float *buffer = chain->combBuffers[c];
                uint32_t index = chain->combIndex[c];
                float output = buffer[index];
                chain->combStore[c] = output * (1.0f - chain->combDamp) + chain->combStore[c] * chain->combDamp;
                buffer[index] = input + chain->combStore[c] * chain->combFeedback;
                index += 1;
                if (index >= chain->combLength[c]) {
                    index = 0;
                }
                chain->combIndex[c] = index;
                sum += output;
            }
            float reverb = sum * 0.25f;
            for (int a = 0; a < 2; a++) {
                float *buffer = chain->allpassBuffers[a];
                uint32_t index = chain->allpassIndex[a];
                float buffered = buffer[index];
                float output = buffered - reverb;
                buffer[index] = reverb + buffered * 0.5f;
                index += 1;
                if (index >= chain->allpassLength[a]) {
                    index = 0;
                }
                chain->allpassIndex[a] = index;
                reverb = output;
            }
            x = x + reverb * p->reverbMix * 1.5f;
        }
        if (p->breathiness > 0.001f) {
            float level = fabsf(x);
            chain->breathEnvelope = level > chain->breathEnvelope ? level : chain->breathEnvelope * chain->breathRelease;
            float noise = mt_random_bipolar(&chain->rng);
            chain->breathHighPass = chain->breathCoefficient * (chain->breathHighPass + noise - chain->breathPreviousNoise);
            chain->breathPreviousNoise = noise;
            x += chain->breathHighPass * chain->breathEnvelope * p->breathiness * 0.6f;
        }
        if (chain->compressorActive) {
            float level = fabsf(x);
            float coefficient = level > chain->compressorEnvelope ? chain->compressorAttack : chain->compressorRelease;
            chain->compressorEnvelope += (level - chain->compressorEnvelope) * coefficient;
            if (chain->compressorCounter == 0) {
                float envelopeDb = 20.0f * log10f(chain->compressorEnvelope + 1e-6f);
                float over = envelopeDb - chain->compressorThresholdDb;
                float gainDb = chain->compressorMakeupDb;
                if (over > 0.0f) {
                    gainDb -= over * (1.0f - 1.0f / chain->compressorRatio);
                }
                chain->compressorTargetGain = powf(10.0f, gainDb / 20.0f);
            }
            chain->compressorCounter = (chain->compressorCounter + 1) % 16;
            chain->compressorGain += (chain->compressorTargetGain - chain->compressorGain) * 0.01f;
            x *= chain->compressorGain;
        }
        x *= chain->gainLinear;
        if (p->wet < 0.999f) {
            x = dry + (x - dry) * p->wet;
        }
        samples[i] = mt_soft_limit(x);
    }
}

static void mt_chain_prepare(MTVoiceChain *chain, uint32_t sampleRate) {
    if (sampleRate == 0) {
        sampleRate = 48000;
    }
    if (chain->sampleRate != sampleRate) {
        mt_chain_configure(chain, sampleRate);
    }
}

void MTVoiceChainPrepare(MTVoiceChain *chain, uint32_t sampleRate) {
    mt_chain_prepare(chain, sampleRate);
}

void MTVoiceChainProcessFloat(MTVoiceChain *chain, float *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0) {
        return;
    }
    mt_chain_prepare(chain, sampleRate);
    if (channels == 1) {
        mt_chain_process_mono(chain, samples, frames);
        return;
    }
    size_t offset = 0;
    while (offset < frames) {
        size_t count = frames - offset;
        if (count > MT_BLOCK_FRAMES) {
            count = MT_BLOCK_FRAMES;
        }
        float scale = 1.0f / (float)channels;
        for (size_t i = 0; i < count; i++) {
            const float *frame = samples + (offset + i) * channels;
            float sum = 0.0f;
            for (size_t c = 0; c < channels; c++) {
                sum += frame[c];
            }
            chain->scratch[i] = sum * scale;
        }
        mt_chain_process_mono(chain, chain->scratch, count);
        for (size_t i = 0; i < count; i++) {
            float *frame = samples + (offset + i) * channels;
            for (size_t c = 0; c < channels; c++) {
                frame[c] = chain->scratch[i];
            }
        }
        offset += count;
    }
}

void MTVoiceChainProcessInt16(MTVoiceChain *chain, int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0) {
        return;
    }
    mt_chain_prepare(chain, sampleRate);
    size_t offset = 0;
    const float scale = 1.0f / 32768.0f;
    while (offset < frames) {
        size_t count = frames - offset;
        if (count > MT_BLOCK_FRAMES) {
            count = MT_BLOCK_FRAMES;
        }
        float channelScale = scale / (float)channels;
        for (size_t i = 0; i < count; i++) {
            const int16_t *frame = samples + (offset + i) * channels;
            float sum = 0.0f;
            for (size_t c = 0; c < channels; c++) {
                sum += (float)frame[c];
            }
            chain->scratch[i] = sum * channelScale;
        }
        mt_chain_process_mono(chain, chain->scratch, count);
        for (size_t i = 0; i < count; i++) {
            int16_t value = mt_float_to_int16(chain->scratch[i]);
            int16_t *frame = samples + (offset + i) * channels;
            for (size_t c = 0; c < channels; c++) {
                frame[c] = value;
            }
        }
        offset += count;
    }
}

void MTVoiceChainCallProcess(void *context, int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (context == NULL) {
        return;
    }
    MTVoiceChainProcessInt16((MTVoiceChain *)context, samples, frames, channels, sampleRate);
}

void MTVoiceChainCallRelease(void *context) {
    MTVoiceChainDestroy((MTVoiceChain *)context);
}

// MARK: - Playback equalizer

static const float mt_eq_frequencies[MTAudioEqualizerBandCount] = { 60.0f, 230.0f, 910.0f, 3600.0f, 14000.0f };

// Seqlock: the writer (control side, serialized by the mutex) makes the counter odd while it writes.
static _Atomic uint32_t mt_eq_sequence = 0;
static _Atomic float mt_eq_gains[MTAudioEqualizerBandCount];
static _Atomic bool mt_eq_kinds[3];
static pthread_mutex_t mt_eq_writer_lock = PTHREAD_MUTEX_INITIALIZER;

float MTAudioEqualizerBandFrequency(int band) {
    if (band < 0 || band >= MTAudioEqualizerBandCount) {
        return 0.0f;
    }
    return mt_eq_frequencies[band];
}

void MTAudioEqualizerSetParameters(const float *gainsDb, bool audio, bool roundVideo, bool video) {
    pthread_mutex_lock(&mt_eq_writer_lock);
    atomic_fetch_add_explicit(&mt_eq_sequence, 1, memory_order_acq_rel);
    for (int i = 0; i < MTAudioEqualizerBandCount; i++) {
        atomic_store_explicit(&mt_eq_gains[i], mt_clampf(gainsDb[i], -12.0f, 12.0f), memory_order_relaxed);
    }
    atomic_store_explicit(&mt_eq_kinds[MTAudioEqualizerKindAudio], audio, memory_order_relaxed);
    atomic_store_explicit(&mt_eq_kinds[MTAudioEqualizerKindRoundVideo], roundVideo, memory_order_relaxed);
    atomic_store_explicit(&mt_eq_kinds[MTAudioEqualizerKindVideo], video, memory_order_relaxed);
    atomic_fetch_add_explicit(&mt_eq_sequence, 1, memory_order_release);
    pthread_mutex_unlock(&mt_eq_writer_lock);
}

/// Reads a consistent copy; false if the writer kept it busy (the caller keeps what it had).
static bool mt_eq_snapshot(float *gains, bool *kinds, uint32_t *sequence) {
    for (int attempt = 0; attempt < 8; attempt++) {
        uint32_t before = atomic_load_explicit(&mt_eq_sequence, memory_order_acquire);
        if ((before & 1u) != 0) {
            continue;
        }
        for (int i = 0; i < MTAudioEqualizerBandCount; i++) {
            gains[i] = atomic_load_explicit(&mt_eq_gains[i], memory_order_relaxed);
        }
        for (int i = 0; i < 3; i++) {
            kinds[i] = atomic_load_explicit(&mt_eq_kinds[i], memory_order_relaxed);
        }
        atomic_thread_fence(memory_order_acquire);
        uint32_t after = atomic_load_explicit(&mt_eq_sequence, memory_order_relaxed);
        if (before == after) {
            *sequence = before;
            return true;
        }
    }
    return false;
}

static bool mt_eq_has_gain(const float *gains) {
    for (int i = 0; i < MTAudioEqualizerBandCount; i++) {
        if (fabsf(gains[i]) > 0.05f) {
            return true;
        }
    }
    return false;
}

bool MTAudioEqualizerIsActiveForKind(MTAudioEqualizerKind kind) {
    if ((int)kind < 0 || (int)kind > 2) {
        return false;
    }
    if (!atomic_load_explicit(&mt_eq_kinds[kind], memory_order_relaxed)) {
        return false;
    }
    for (int i = 0; i < MTAudioEqualizerBandCount; i++) {
        if (fabsf(atomic_load_explicit(&mt_eq_gains[i], memory_order_relaxed)) > 0.05f) {
            return true;
        }
    }
    return false;
}

struct MTAudioEqualizer {
    MTAudioEqualizerKind kind;
    uint32_t sequence;
    bool hasSnapshot;
    uint32_t sampleRate;
    bool active;
    float gains[MTAudioEqualizerBandCount];
    float preamp;
    MTBiquad coefficients[MTAudioEqualizerBandCount];
    float state[MT_MAX_CHANNELS][MTAudioEqualizerBandCount][2];
};

MTAudioEqualizer *MTAudioEqualizerCreate(MTAudioEqualizerKind kind) {
    MTAudioEqualizer *equalizer = (MTAudioEqualizer *)calloc(1, sizeof(MTAudioEqualizer));
    if (equalizer == NULL) {
        return NULL;
    }
    equalizer->kind = kind;
    equalizer->preamp = 1.0f;
    for (int i = 0; i < MTAudioEqualizerBandCount; i++) {
        mt_biquad_identity(&equalizer->coefficients[i]);
    }
    return equalizer;
}

void MTAudioEqualizerDestroy(MTAudioEqualizer *equalizer) {
    free(equalizer);
}

static void mt_eq_compute(const float *gains, float sampleRate, MTBiquad *coefficients, float *preamp) {
    float maxBoost = 0.0f;
    for (int i = 0; i < MTAudioEqualizerBandCount; i++) {
        float gain = gains[i];
        if (gain > maxBoost) {
            maxBoost = gain;
        }
        if (fabsf(gain) <= 0.05f) {
            mt_biquad_identity(&coefficients[i]);
        } else if (i == 0) {
            mt_biquad_low_shelf(&coefficients[i], sampleRate, mt_eq_frequencies[i], gain);
        } else if (i == MTAudioEqualizerBandCount - 1) {
            mt_biquad_high_shelf(&coefficients[i], sampleRate, mt_eq_frequencies[i], gain);
        } else {
            mt_biquad_peak(&coefficients[i], sampleRate, mt_eq_frequencies[i], 1.0f, gain);
        }
    }
    // Half of the strongest boost as headroom: boosted bands do not clip the rest.
    *preamp = powf(10.0f, -0.5f * maxBoost / 20.0f);
}

/// Picks up a new parameter set or sample rate. The filter states are kept: no click on a change.
static void mt_eq_refresh(MTAudioEqualizer *equalizer, uint32_t sampleRate) {
    uint32_t current = atomic_load_explicit(&mt_eq_sequence, memory_order_acquire);
    if (equalizer->hasSnapshot && current == equalizer->sequence && sampleRate == equalizer->sampleRate) {
        return;
    }
    float gains[MTAudioEqualizerBandCount];
    bool kinds[3];
    uint32_t sequence = 0;
    if (!mt_eq_snapshot(gains, kinds, &sequence)) {
        return;
    }
    bool wasActive = equalizer->active;
    equalizer->hasSnapshot = true;
    equalizer->sequence = sequence;
    equalizer->sampleRate = sampleRate;
    equalizer->active = kinds[equalizer->kind] && mt_eq_has_gain(gains);
    memcpy(equalizer->gains, gains, sizeof(gains));
    if (equalizer->active) {
        mt_eq_compute(gains, (float)sampleRate, equalizer->coefficients, &equalizer->preamp);
        if (!wasActive) {
            memset(equalizer->state, 0, sizeof(equalizer->state));
        }
    }
}

static inline float mt_eq_run(MTAudioEqualizer *equalizer, size_t channel, float x) {
    x *= equalizer->preamp;
    for (int b = 0; b < MTAudioEqualizerBandCount; b++) {
        const MTBiquad *f = &equalizer->coefficients[b];
        float *z = equalizer->state[channel][b];
        float y = f->b0 * x + z[0];
        z[0] = f->b1 * x - f->a1 * y + z[1];
        z[1] = f->b2 * x - f->a2 * y;
        x = y;
    }
    return x;
}

void MTAudioEqualizerProcessInt16(MTAudioEqualizer *equalizer, int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0 || sampleRate == 0) {
        return;
    }
    mt_eq_refresh(equalizer, sampleRate);
    if (!equalizer->active) {
        return;
    }
    size_t processedChannels = channels > MT_MAX_CHANNELS ? MT_MAX_CHANNELS : channels;
    const float scale = 1.0f / 32768.0f;
    for (size_t i = 0; i < frames; i++) {
        int16_t *frame = samples + i * channels;
        for (size_t c = 0; c < processedChannels; c++) {
            frame[c] = mt_float_to_int16(mt_eq_run(equalizer, c, (float)frame[c] * scale));
        }
    }
}

void MTAudioEqualizerProcessFloat(MTAudioEqualizer *equalizer, float *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (frames == 0 || channels == 0 || sampleRate == 0) {
        return;
    }
    mt_eq_refresh(equalizer, sampleRate);
    if (!equalizer->active) {
        return;
    }
    size_t processedChannels = channels > MT_MAX_CHANNELS ? MT_MAX_CHANNELS : channels;
    for (size_t i = 0; i < frames; i++) {
        float *frame = samples + i * channels;
        for (size_t c = 0; c < processedChannels; c++) {
            frame[c] = mt_soft_limit(mt_eq_run(equalizer, c, frame[c]));
        }
    }
}

void MTAudioEqualizerProcessOffline(const float *gainsDb, float *samples, size_t frames, uint32_t sampleRate) {
    if (frames == 0 || sampleRate == 0) {
        return;
    }
    float gains[MTAudioEqualizerBandCount];
    for (int i = 0; i < MTAudioEqualizerBandCount; i++) {
        gains[i] = mt_clampf(gainsDb[i], -12.0f, 12.0f);
    }
    if (!mt_eq_has_gain(gains)) {
        return;
    }
    MTAudioEqualizer equalizer;
    memset(&equalizer, 0, sizeof(equalizer));
    equalizer.active = true;
    mt_eq_compute(gains, (float)sampleRate, equalizer.coefficients, &equalizer.preamp);
    for (size_t i = 0; i < frames; i++) {
        samples[i] = mt_soft_limit(mt_eq_run(&equalizer, 0, samples[i]));
    }
}
