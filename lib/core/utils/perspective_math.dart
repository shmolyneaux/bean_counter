import 'package:flutter/widgets.dart';

/// Computes the 3x3 homography matrix (as a 4x4 Flutter Matrix4) 
/// mapping an arbitrary quadrilateral to a rectangular bounding box.
class PerspectiveMath {
  /// Computes a Matrix4 that distorts a given 4-point quadrilateral (src)
  /// so that it fits perfectly into the specified rectangle (dest).
  ///
  /// The resulting Matrix4 can be supplied directly to a `Transform` widget.
  static Matrix4 getPerspectiveTransform({
    required Offset srcTl,
    required Offset srcTr,
    required Offset srcBr,
    required Offset srcBl,
    required double destWidth,
    required double destHeight,
  }) {
    // We want to map:
    // srcTl -> (0, 0)
    // srcTr -> (destWidth, 0)
    // srcBr -> (destWidth, destHeight)
    // srcBl -> (0, destHeight)

    final src = [srcTl, srcTr, srcBr, srcBl];
    final dest = [
      const Offset(0, 0),
      Offset(destWidth, 0),
      Offset(destWidth, destHeight),
      Offset(0, destHeight),
    ];

    // Assembly 8x8 matrix A and 8x1 right-hand side B.
    // For each point:
    // x * h0 + y * h1 + h2 - x * u * h6 - y * u * h7 = u
    // x * h3 + y * h4 + h5 - x * v * h6 - y * v * h7 = v
    List<List<double>> a = List.generate(8, (_) => List.filled(8, 0.0));
    List<double> b = List.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      double x = src[i].dx;
      double y = src[i].dy;
      double u = dest[i].dx;
      double v = dest[i].dy;

      // Equation 1 for u
      a[i * 2][0] = x;
      a[i * 2][1] = y;
      a[i * 2][2] = 1;
      a[i * 2][3] = 0;
      a[i * 2][4] = 0;
      a[i * 2][5] = 0;
      a[i * 2][6] = -x * u;
      a[i * 2][7] = -y * u;
      b[i * 2] = u;

      // Equation 2 for v
      a[i * 2 + 1][0] = 0;
      a[i * 2 + 1][1] = 0;
      a[i * 2 + 1][2] = 0;
      a[i * 2 + 1][3] = x;
      a[i * 2 + 1][4] = y;
      a[i * 2 + 1][5] = 1;
      a[i * 2 + 1][6] = -x * v;
      a[i * 2 + 1][7] = -y * v;
      b[i * 2 + 1] = v;
    }

    final h = _gaussianElimination(a, b);
    if (h == null) {
      // If singular, return identity.
      return Matrix4.identity();
    }

    // Assembly into Flutter's 4x4 matrix.
    // Flutter Matrix4 is column-major!
    // A standard 3x3 homography:
    // [ h0, h1, h2 ]
    // [ h3, h4, h5 ]
    // [ h6, h7, 1  ]
    // 
    // Embedded into 4x4 (mapping 2D X, Y, and homogeneous W, keeping Z unchanged):
    // [ h0, h1, 0, h2 ]
    // [ h3, h4, 0, h5 ]
    // [  0,  0, 1,  0 ]
    // [ h6, h7, 0,  1 ]
    return Matrix4(
      h[0], h[3], 0.0, h[6],  // Col 1
      h[1], h[4], 0.0, h[7],  // Col 2
      0.0,  0.0,  1.0, 0.0,   // Col 3
      h[2], h[5], 0.0, 1.0,   // Col 4
    );
  }

  /// Solves Ax = B where A is 8x8 and B is 8x1 using Gaussian Elimination with partial pivoting.
  static List<double>? _gaussianElimination(List<List<double>> a, List<double> b) {
    int n = 8;
    for (int i = 0; i < n; i++) {
      // Pivot
      double maxEl = a[i][i].abs();
      int maxRow = i;
      for (int k = i + 1; k < n; k++) {
        if (a[k][i].abs() > maxEl) {
          maxEl = a[k][i].abs();
          maxRow = k;
        }
      }

      if (maxEl < 1e-10) return null; // Singular matrix

      // Swap rows
      final tempRow = a[i];
      a[i] = a[maxRow];
      a[maxRow] = tempRow;
      final tempB = b[i];
      b[i] = b[maxRow];
      b[maxRow] = tempB;

      // Eliminate
      for (int k = i + 1; k < n; k++) {
        double c = -a[k][i] / a[i][i];
        for (int j = i; j < n; j++) {
          if (i == j) {
            a[k][j] = 0;
          } else {
            a[k][j] += c * a[i][j];
          }
        }
        b[k] += c * b[i];
      }
    }

    // Back substitution
    List<double> x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      x[i] = b[i];
      for (int k = i + 1; k < n; k++) {
        x[i] -= a[i][k] * x[k];
      }
      x[i] /= a[i][i];
    }
    return x;
  }
}
