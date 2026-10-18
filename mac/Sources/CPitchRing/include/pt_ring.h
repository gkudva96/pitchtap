#ifndef PT_RING_H
#define PT_RING_H

#include <stddef.h>
#include <stdint.h>

// Single-producer / single-consumer stereo float ring buffer, lock-free and
// allocation-free after creation, so both ends can run on real-time threads.
// Producer: the Core Audio IOProc (tap input). Consumer: the AVAudioSourceNode.

typedef struct PTRing PTRing;

PTRing *pt_ring_create(size_t capacityFrames);
void pt_ring_destroy(PTRing *ring);

// Producer side. `stride` is the distance in floats between consecutive frames
// of the same channel (2 for interleaved stereo, 1 for planar). Returns frames
// written; frames that don't fit are dropped.
size_t pt_ring_write(PTRing *ring, const float *left, const float *right, size_t frames, size_t stride);

// Consumer side. Reads into planar buffers; returns frames read.
size_t pt_ring_read(PTRing *ring, float *left, float *right, size_t frames);
void pt_ring_skip(PTRing *ring, size_t frames);
void pt_ring_clear(PTRing *ring);

size_t pt_ring_fill(PTRing *ring);
uint64_t pt_ring_total_written(PTRing *ring);

// True if every sample in the buffer is exactly zero.
int pt_is_silent(const float *samples, size_t count);

#endif
