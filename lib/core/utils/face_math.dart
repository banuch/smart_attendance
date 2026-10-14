import 'dart:math' as math;

List<double> l2Normalize(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final norm = math.sqrt(sum);
  if (norm == 0) return List<double>.from(v);
  return [for (final x in v) x / norm];
}

/// Cosine similarity in [-1, 1]. Returns 0 for mismatched or empty vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) return 0;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}
