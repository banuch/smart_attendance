import { cosineSimilarity } from './face.js';

export const FlagReason = {
  faceMismatch: 'face_mismatch',
  faceNotVerified: 'face_not_verified',
  lowGpsAccuracy: 'low_gps_accuracy',
};

/**
 * Face score and review flags for a punch. A missing or incomparable
 * embedding does not block the punch; it is flagged for the admin instead.
 */
export function evaluatePunch({ embedding, enrolledEmbedding, accuracy }, config) {
  const reasons = [];
  let faceScore = null;
  if (embedding?.length && enrolledEmbedding?.length === embedding.length) {
    faceScore = cosineSimilarity(embedding, enrolledEmbedding);
    if (faceScore < config.faceMatchThreshold) reasons.push(FlagReason.faceMismatch);
  } else {
    reasons.push(FlagReason.faceNotVerified);
  }
  if (accuracy > config.maxGpsAccuracyMeters) reasons.push(FlagReason.lowGpsAccuracy);
  return { faceScore, reasons };
}

/** Record-level flags after a check-out: flagged sticks, approval is lost. */
export function afterCheckOut(record, outReasons) {
  const outFlagged = outReasons.length > 0;
  return {
    flagged: record.flagged || outFlagged,
    reviewed: record.reviewed && !outFlagged,
  };
}
