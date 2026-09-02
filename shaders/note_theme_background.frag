#include <flutter/runtime_effect.glsl>

// One deliberately small RuntimeEffect serves every expressive note theme.
// Only one branch runs for a given draw and no texture samples or loops are
// used, keeping the full-screen background inexpensive on mobile GPUs.
uniform vec2 uSize;
uniform float uProgress;
uniform float uTheme;
uniform float uOpacity;
uniform vec4 uPrimary;
uniform vec4 uSecondary;
uniform vec4 uTertiary;

out vec4 fragColor;

const float PI = 3.14159265358979323846;

float softLine(float distanceToLine, float core, float feather) {
  return 1.0 - smoothstep(core, core + feather, distanceToLine);
}

void finish(vec3 premultipliedTint, float alpha) {
  float scaledAlpha = clamp(alpha * uOpacity, 0.0, 0.32);
  float sourceAlpha = max(alpha, 0.0001);
  vec3 sourceColor = premultipliedTint / sourceAlpha;
  fragColor = vec4(sourceColor * scaledAlpha, scaledAlpha);
}

void paintAurora(vec2 uv, float time) {
  float firstCenter = 0.20 + 0.070 * sin(uv.x * 4.2 + time);
  float secondCenter = 0.51 + 0.085 * sin(uv.x * 3.4 - time * 0.72 + 2.1);
  float thirdCenter = 0.80 + 0.060 * sin(uv.x * 4.8 + time * 0.55 + 4.0);

  float first = softLine(abs(uv.y - firstCenter), 0.015, 0.145) * 0.070;
  float second = softLine(abs(uv.y - secondCenter), 0.012, 0.125) * 0.060;
  float third = softLine(abs(uv.y - thirdCenter), 0.010, 0.105) * 0.050;
  float alpha = first + second + third;
  vec3 tint = uPrimary.rgb * first + uTertiary.rgb * second
      + uSecondary.rgb * third;
  finish(tint, alpha);
}

void paintCitrus(vec2 uv, float time) {
  vec2 cells = vec2(3.2, 4.4);
  vec2 cell = floor(uv * cells);
  vec2 point = fract(uv * cells + vec2(time * 0.035, -time * 0.022)) - 0.5;
  point.x *= uSize.x / max(uSize.y, 1.0) * cells.y / cells.x;

  float rotation = time * 0.08 + (cell.x + cell.y) * 0.34;
  float sine = sin(rotation);
  float cosine = cos(rotation);
  point = mat2(cosine, -sine, sine, cosine) * point;

  float radius = length(point);
  float rind = softLine(abs(radius - 0.255), 0.010, 0.020);
  float segmentDistance = min(
    abs(point.y),
    min(abs(point.y - point.x * 0.577), abs(point.y + point.x * 0.577))
  );
  float segments = softLine(segmentDistance, 0.004, 0.012)
      * (1.0 - smoothstep(0.20, 0.26, radius));
  float flesh = (1.0 - smoothstep(0.19, 0.25, radius)) * 0.32;
  float alpha = (rind * 0.105 + segments * 0.060 + flesh * 0.038);
  float alternate = step(1.0, mod(cell.x + cell.y, 2.0));
  vec3 fruitColor = mix(uPrimary.rgb, uTertiary.rgb, alternate * 0.62);
  finish(fruitColor * alpha, alpha);
}

void paintBotanical(vec2 uv, float time) {
  vec2 cells = vec2(3.0, 4.2);
  vec2 cell = floor(uv * cells);
  vec2 point = fract(uv * cells + vec2(time * 0.018, -time * 0.028)) - 0.5;
  point.x *= uSize.x / max(uSize.y, 1.0) * cells.y / cells.x;

  float direction = mix(-0.72, 0.62, step(1.0, mod(cell.x + cell.y, 2.0)));
  float sway = sin(time + cell.x * 1.7 + cell.y) * 0.10;
  float sine = sin(direction + sway);
  float cosine = cos(direction + sway);
  point = mat2(cosine, -sine, sine, cosine) * point;

  // A tapered ellipse reads as a leaf while remaining cheap to evaluate.
  vec2 leafPoint = vec2((point.x + 0.02) / 0.32, point.y / 0.115);
  float taper = 1.0 + abs(leafPoint.x) * 0.70;
  float leafDistance = length(vec2(leafPoint.x, leafPoint.y * taper));
  float leaf = 1.0 - smoothstep(0.82, 1.0, leafDistance);
  float vein = softLine(abs(point.y), 0.003, 0.010)
      * (1.0 - smoothstep(0.04, 0.30, abs(point.x)));
  float alpha = leaf * 0.055 + vein * 0.085;
  float alternate = step(1.0, mod(cell.x, 2.0));
  vec3 leafColor = mix(uPrimary.rgb, uTertiary.rgb, alternate * 0.70);
  finish(leafColor * alpha, alpha);
}

void paintNeon(vec2 uv, float time) {
  float horizontal = abs(fract((uv.y - time * 0.018) * 8.0) - 0.5);
  float diagonal = abs(fract((uv.x + uv.y * 0.22 + time * 0.012) * 7.0) - 0.5);
  float gridCore = max(
    softLine(horizontal, 0.006, 0.012),
    softLine(diagonal, 0.006, 0.012)
  );
  float gridGlow = max(
    softLine(horizontal, 0.010, 0.050),
    softLine(diagonal, 0.010, 0.050)
  );

  vec2 framePoint = fract(uv * vec2(2.2, 3.1) + vec2(time * 0.025, -time * 0.018)) - 0.5;
  vec2 frameDistance = abs(framePoint) - vec2(0.24, 0.17);
  float frame = softLine(abs(max(frameDistance.x, frameDistance.y)), 0.006, 0.015);
  float alpha = gridGlow * 0.028 + gridCore * 0.075 + frame * 0.075;
  vec3 tint = uPrimary.rgb * (gridGlow * 0.028 + gridCore * 0.075)
      + uTertiary.rgb * (frame * 0.075);
  finish(tint, alpha);
}

void paintEditorial(vec2 uv, float time) {
  float shiftedY = uv.y + time * 0.010;
  float rules = softLine(abs(fract(shiftedY * 10.0) - 0.5), 0.006, 0.012);
  float margin = softLine(abs(uv.x - 0.115), 0.002, 0.006);

  vec2 blockCell = fract(vec2(uv.x * 2.0, shiftedY * 5.0)) - 0.5;
  float block = (1.0 - step(0.25, abs(blockCell.x)))
      * (1.0 - step(0.11, abs(blockCell.y)));
  float column = step(0.5, fract(floor(shiftedY * 5.0) * 0.5));
  float alpha = rules * 0.050 + margin * 0.105 + block * 0.040;
  vec3 tint = uPrimary.rgb * (rules * 0.050 + block * 0.040)
      + mix(uPrimary.rgb, uTertiary.rgb, 0.78) * (margin * 0.105)
      + uTertiary.rgb * (block * column * 0.018);
  finish(tint, alpha);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  float time = uProgress * PI * 2.0;

  if (uTheme < 1.5) {
    paintAurora(uv, time);
  } else if (uTheme < 2.5) {
    paintCitrus(uv, time);
  } else if (uTheme < 3.5) {
    paintBotanical(uv, time);
  } else if (uTheme < 4.5) {
    paintNeon(uv, time);
  } else {
    paintEditorial(uv, time);
  }
}
