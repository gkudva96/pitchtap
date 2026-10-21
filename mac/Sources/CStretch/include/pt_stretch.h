#ifndef PT_STRETCH_H
#define PT_STRETCH_H

#ifdef __cplusplus
extern "C" {
#endif

// Stereo pitch shifter (Signalsmith Stretch), same length in as out, so the tempo never changes.
// Create and destroy off the audio thread; pt_stretch_process allocates nothing and is meant for
// the real-time render thread. The setters may be called from any thread and take effect on the
// next process call.

typedef struct PTStretch PTStretch;

PTStretch *pt_stretch_create(double sampleRate);
void pt_stretch_destroy(PTStretch *stretch);

void pt_stretch_set_semitones(PTStretch *stretch, float semitones);

// Processes `frames` frames from the planar input into the planar output (they may not alias).
void pt_stretch_process(PTStretch *stretch, const float *inLeft, const float *inRight,
                        float *outLeft, float *outRight, int frames);

#ifdef __cplusplus
}
#endif

#endif
