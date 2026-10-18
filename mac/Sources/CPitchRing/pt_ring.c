#include "pt_ring.h"

#include <stdatomic.h>
#include <stdlib.h>

struct PTRing {
    float *data; // interleaved stereo
    size_t capacity;
    _Atomic uint64_t writePos; // monotonically increasing frame counters
    _Atomic uint64_t readPos;
};

PTRing *pt_ring_create(size_t capacityFrames) {
    PTRing *ring = calloc(1, sizeof(PTRing));
    if (!ring) return NULL;
    ring->data = calloc(capacityFrames * 2, sizeof(float));
    if (!ring->data) {
        free(ring);
        return NULL;
    }
    ring->capacity = capacityFrames;
    return ring;
}

void pt_ring_destroy(PTRing *ring) {
    if (!ring) return;
    free(ring->data);
    free(ring);
}

size_t pt_ring_write(PTRing *ring, const float *left, const float *right, size_t frames, size_t stride) {
    uint64_t w = atomic_load_explicit(&ring->writePos, memory_order_relaxed);
    uint64_t r = atomic_load_explicit(&ring->readPos, memory_order_acquire);
    size_t space = ring->capacity - (size_t)(w - r);
    size_t n = frames < space ? frames : space;
    for (size_t i = 0; i < n; i++) {
        size_t idx = (size_t)((w + i) % ring->capacity) * 2;
        ring->data[idx] = left[i * stride];
        ring->data[idx + 1] = right[i * stride];
    }
    atomic_store_explicit(&ring->writePos, w + n, memory_order_release);
    return n;
}

size_t pt_ring_read(PTRing *ring, float *left, float *right, size_t frames) {
    uint64_t r = atomic_load_explicit(&ring->readPos, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&ring->writePos, memory_order_acquire);
    size_t avail = (size_t)(w - r);
    size_t n = frames < avail ? frames : avail;
    for (size_t i = 0; i < n; i++) {
        size_t idx = (size_t)((r + i) % ring->capacity) * 2;
        left[i] = ring->data[idx];
        right[i] = ring->data[idx + 1];
    }
    atomic_store_explicit(&ring->readPos, r + n, memory_order_release);
    return n;
}

void pt_ring_skip(PTRing *ring, size_t frames) {
    uint64_t r = atomic_load_explicit(&ring->readPos, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&ring->writePos, memory_order_acquire);
    size_t avail = (size_t)(w - r);
    atomic_store_explicit(&ring->readPos, r + (frames < avail ? frames : avail), memory_order_release);
}

void pt_ring_clear(PTRing *ring) {
    atomic_store_explicit(&ring->readPos, atomic_load_explicit(&ring->writePos, memory_order_acquire),
                          memory_order_release);
}

size_t pt_ring_fill(PTRing *ring) {
    uint64_t w = atomic_load_explicit(&ring->writePos, memory_order_acquire);
    uint64_t r = atomic_load_explicit(&ring->readPos, memory_order_acquire);
    return (size_t)(w - r);
}

uint64_t pt_ring_total_written(PTRing *ring) {
    return atomic_load_explicit(&ring->writePos, memory_order_acquire);
}

int pt_is_silent(const float *samples, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (samples[i] != 0.0f) return 0;
    }
    return 1;
}
