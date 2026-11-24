#pragma once
#include <cmath>
#include <cstdint>

// Detector para o pulso. Quatro picos com cadência plausível
// confirmam uma sequência; picos próximos demais não são passadas novas.
class StepCounter {
 public:
  // Diagnóstico de cada amostra; não muda as decisões do detector.
  enum class Event : uint8_t {
    SAMPLE = 0, FIRST_PEAK = 1, TOO_CLOSE = 2, RESTART_GAP = 3,
    RESTART_CADENCE = 4, CANDIDATE = 5, CONFIRMED = 6, COUNTED = 7,
    INVALID_SAMPLE = 8, SAMPLE_GAP = 9, EARLY_CADENCE = 10, MOTION_ARTIFACT = 11
  };
  uint32_t steps = 0;
  void reset() { *this = StepCounter(); }
  void breakSequence() {
    initialized = false;
    streak = cadenceMs = 0;
    weakStreak = false;
    armed = true;
    if (artifact != Artifact::BLOCKED) artifact = Artifact::NONE;
  }
  float filteredAcceleration() const { return filtered; }
  uint32_t cadenceInterval() const { return cadenceMs; }
  uint32_t pendingPeaks() const {
    if (artifact == Artifact::CONFIRMING) return 1;
    return streak < CONFIRM_PEAKS ? streak : 0;
  }
  Event lastEvent() const { return event; }
  void add(uint32_t now, float x, float y, float z, float gx = 0, float gy = 0, float gz = 0) {
    event = Event::SAMPLE;
    const float magnitude = std::sqrt(x*x + y*y + z*z);
    const float rotation = std::sqrt(gx*gx + gy*gy + gz*gz);
    if (!std::isfinite(magnitude) || !std::isfinite(rotation) || magnitude < 0.2f || magnitude > 3.5f) {
      blockArtifact(now);
      event = Event::INVALID_SAMPLE; return;
    }
    if (ignoreArtifact(now, rotation)) return;
    if (!initialized || now - lastSample > MAX_SAMPLE_GAP_MS || recoveryExpired(lastSample)) {
      breakSequence();
      baseline = magnitude; filtered = variation = 0; initialized = true; lastSample = now;
      event = Event::SAMPLE_GAP; return;
    }
    const uint32_t peakAt = lastSample;
    lastSample = now;
    baseline += 0.02f * (magnitude - baseline);
    // Com amostras a ~50 Hz, reduz oscilações rápidas dentro de uma passada.
    const float previous = filtered;
    filtered += 0.25f * (magnitude - baseline - filtered);
    variation += 0.05f * (std::fabs(filtered - previous) - variation);
    if (previous < REARM_G) armed = true;
    const bool tracking = streak >= CONFIRM_PEAKS && peakAt - lastPeak <= MAX_STEP_MS;
    const float startThreshold = std::fmin(PEAK_G, MIN_START_G + 1.5f * variation);
    const bool recovering = artifact == Artifact::REACQUIRE || artifact == Artifact::CONFIRMING;
    const float peakThreshold = tracking || recovering ? TRACK_PEAK_G : startThreshold;
    // Use o topo do pico para distinguir um impacto leve de um que ainda está subindo.
    if (!armed || previous < peakThreshold || filtered >= previous) return;
    armed = false;
    if (recovering) {
      recoverAfterRotation(peakAt);
      return;
    }
    const bool weakPeak = previous < PEAK_G;
    if (!streak) {
      streak = 1; weakStreak = weakPeak; lastPeak = peakAt; event = Event::FIRST_PEAK; return;
    }
    const uint32_t interval = peakAt - lastPeak;
    if (interval < MIN_STEP_MS) { event = Event::TOO_CLOSE; return; }
    const bool weakConfirmation = streak < CONFIRM_PEAKS && (weakStreak || weakPeak);
    // Um pico antecipado não substitui a referência da passada anterior.
    // Reiniciar aqui desorganizava uma sequência válida por um pico extra.
    if (streak >= 2 && interval * 100u < cadenceMs * (weakConfirmation ? 75u : 50u)) {
      event = Event::EARLY_CADENCE; return;
    }
    lastPeak = peakAt;
    // A partida e a desaceleração podem mudar o intervalo em mais de 30%.
    // Não descartar esses passos; manter os limites de frequência e amplitude.
    if (interval > MAX_STEP_MS || (streak >= 2 &&
         interval * 100u > cadenceMs * (weakConfirmation ? 125u : 150u))) {
      streak = 1; cadenceMs = 0; weakStreak = weakPeak;
      event = interval > MAX_STEP_MS ? Event::RESTART_GAP : Event::RESTART_CADENCE;
      return;
    }
    weakStreak = weakStreak || weakPeak;
    if (streak == 1) { streak = 2; cadenceMs = interval; event = Event::CANDIDATE; return; }
    cadenceMs = (cadenceMs * 3u + interval) / 4u;
    if (streak < CONFIRM_PEAKS) {
      ++streak;
      event = Event::CANDIDATE;
      if (streak == CONFIRM_PEAKS) { steps += CONFIRM_PEAKS; event = Event::CONFIRMED; }
    } else {
      ++steps;
      event = Event::COUNTED;
    }
  }
 private:
  enum class Artifact { NONE, BLOCKED, SETTLING, REACQUIRE, CONFIRMING };

  bool recoveryExpired(uint32_t sample) const {
    if (artifact == Artifact::REACQUIRE) return (sample - lastPeak) * 5u > cadenceMs * 11u;
    return artifact == Artifact::CONFIRMING && (sample - recoveryPeak) * 5u > cadenceMs * 6u;
  }

  void recoverAfterRotation(uint32_t peak) {
    const bool confirming = artifact == Artifact::CONFIRMING;
    const uint32_t interval = peak - (confirming ? recoveryPeak : lastPeak);
    // Pode haver um pico encoberto pelo giro; só os dois picos observados entram no total.
    const uint32_t expected = !confirming && interval * 2u > cadenceMs * 3u ? 2 * cadenceMs : cadenceMs;
    const uint32_t error = interval > expected ? interval - expected : expected - interval;
    if (interval < MIN_STEP_MS || error * 5u > cadenceMs) {
      event = Event::MOTION_ARTIFACT;
      return;
    }
    if (!confirming) {
      recoveryPeak = peak;
      artifact = Artifact::CONFIRMING;
      event = Event::CANDIDATE;
      return;
    }
    cadenceMs = (cadenceMs * 3u + interval) / 4u;
    lastPeak = peak;
    steps += 2;
    artifact = Artifact::NONE;
    event = Event::CONFIRMED;
  }

  void blockArtifact(uint32_t now) {
    breakSequence();
    artifact = Artifact::BLOCKED;
    artifactSince = now;
  }

  bool ignoreArtifact(uint32_t now, float rotation) {
    if (rotation > MAX_ROTATION_DPS) {
      if (artifact == Artifact::NONE && streak >= CONFIRM_PEAKS &&
          now - lastSample <= MAX_SAMPLE_GAP_MS && now - lastPeak <= MAX_STEP_MS &&
          (now - lastPeak) * 2u <= cadenceMs * 3u) {
        artifact = Artifact::SETTLING;
        rotationStarted = now;
      }
      if (artifact != Artifact::SETTLING || now - rotationStarted > MAX_BRIEF_ROTATION_MS) {
        blockArtifact(now);
      } else {
        artifactSince = now;
      }
    } else if (artifact == Artifact::BLOCKED && now - artifactSince >= ARTIFACT_HOLDOFF_MS) {
      artifact = Artifact::NONE;
    } else if (artifact == Artifact::SETTLING && now - artifactSince >= SETTLE_MS) {
      if (now - artifactSince > MAX_SAMPLE_GAP_MS) {
        breakSequence();
      } else {
        artifact = Artifact::REACQUIRE;
        filtered = 0;
        lastSample = now;
        armed = true;
        event = Event::MOTION_ARTIFACT;
        return true;
      }
    }
    if (artifact != Artifact::BLOCKED && artifact != Artifact::SETTLING) return false;
    event = Event::MOTION_ARTIFACT;
    return true;
  }

  static constexpr uint32_t MIN_STEP_MS = 320, MAX_STEP_MS = 1500;
  static constexpr uint32_t MAX_SAMPLE_GAP_MS = 200;
  static constexpr uint32_t ARTIFACT_HOLDOFF_MS = 1200;
  static constexpr uint32_t MAX_BRIEF_ROTATION_MS = 120, SETTLE_MS = 80;
  static constexpr float MAX_ROTATION_DPS = 400;
  static constexpr uint32_t CONFIRM_PEAKS = 4;
  static constexpr float REARM_G = 0.02f, PEAK_G = 0.11f, TRACK_PEAK_G = 0.06f, MIN_START_G = 0.072f;
  bool initialized = false, armed = true, weakStreak = false;
  Artifact artifact = Artifact::NONE;
  Event event = Event::SAMPLE;
  float baseline = 1, filtered = 0, variation = 0;
  uint32_t lastSample = 0, lastPeak = 0, cadenceMs = 0, streak = 0;
  uint32_t artifactSince = 0, rotationStarted = 0, recoveryPeak = 0;
};

inline float estimatedDistanceKm(uint32_t steps, float stepLengthM) {
  return stepLengthM > 0 ? steps * stepLengthM / 1000.0f : NAN;
}
inline float estimatedCalories(uint64_t activeMs, float weightKg, float met) {
  // Energia bruta por MET; intensidade informada no perfil, não medida pelo sensor.
  return weightKg > 0 && met > 0 ? met * weightKg * activeMs / 3600000.0f : NAN;
}
