#include "pt_stretch.h"

#include <atomic>
#include <cmath>

#include "signalsmith-stretch/signalsmith-stretch.h"

struct PTStretch {
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    float sampleRate = 48000;
    std::atomic<float> semitones{0};
    float appliedSemitones = NAN; // audio thread only
};

// Above this, timbre is kept rather than transposed (the value Signalsmith's README suggests),
// which tames the metallic, phasey sound of shifted cymbals and air.
static constexpr float tonalityLimitHz = 8000;

PTStretch *pt_stretch_create(double sampleRate) {
    auto *s = new PTStretch();
    s->sampleRate = float(sampleRate);
    s->stretch.presetDefault(2, float(sampleRate));
    return s;
}

void pt_stretch_destroy(PTStretch *stretch) {
    delete stretch;
}

void pt_stretch_set_semitones(PTStretch *stretch, float semitones) {
    stretch->semitones.store(semitones, std::memory_order_relaxed);
}

void pt_stretch_process(PTStretch *stretch, const float *inLeft, const float *inRight,
                        float *outLeft, float *outRight, int frames) {
    float semitones = stretch->semitones.load(std::memory_order_relaxed);
    if (semitones != stretch->appliedSemitones) {
        stretch->stretch.setTransposeSemitones(semitones, tonalityLimitHz / stretch->sampleRate);
        stretch->appliedSemitones = semitones;
    }
    const float *inputs[2] = {inLeft, inRight};
    float *outputs[2] = {outLeft, outRight};
    stretch->stretch.process(inputs, frames, outputs, frames);
}
