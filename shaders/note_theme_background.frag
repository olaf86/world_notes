#include <flutter/runtime_effect.glsl>

// One deliberately small RuntimeEffect serves every expressive note theme.
// Only one branch runs for a given draw and no texture samples or loops are
// used, keeping the full-screen background inexpensive on mobile GPUs.
uniform vec2 uSize;
uniform float uProgress;
uniform float uSeed;
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

// A small, arithmetic-only hash provides stable pseudo-random values for the
// lifetime of a background. It requires no texture lookup or iterative noise.
float seededHash(vec2 value) {
  value += vec2(uSeed * 91.7, uSeed * 47.3);
  vec3 parts = fract(vec3(value.xyx) * vec3(0.1031, 0.1030, 0.0973));
  parts += dot(parts, parts.yzx + 33.33);
  return fract((parts.x + parts.y) * parts.z);
}

float seededValue(float stream) {
  return fract(uSeed * (71.37 + stream * 13.91) + stream * 0.618033);
}

float remix(float value) {
  return fract(value * 7.31 + 0.17);
}

void finish(vec3 premultipliedTint, float alpha) {
  float scaledAlpha = clamp(alpha * uOpacity, 0.0, 0.32);
  float sourceAlpha = max(alpha, 0.0001);
  vec3 sourceColor = premultipliedTint / sourceAlpha;
  fragColor = vec4(sourceColor * scaledAlpha, scaledAlpha);
}

void paintAurora(vec2 uv, float time) {
  float firstRandom = seededValue(1.0);
  float secondRandom = seededValue(2.0);
  float thirdRandom = seededValue(3.0);
  float firstCenter = 0.18 + firstRandom * 0.045
      + mix(0.050, 0.085, firstRandom)
      * sin(uv.x * mix(3.7, 4.8, firstRandom) + time + firstRandom * PI * 2.0);
  float secondCenter = 0.49 + secondRandom * 0.040
      + mix(0.060, 0.095, secondRandom)
      * sin(uv.x * mix(3.0, 4.1, secondRandom) - time + secondRandom * PI * 2.0);
  float thirdCenter = 0.78 + thirdRandom * 0.030
      + mix(0.045, 0.070, thirdRandom)
      * sin(uv.x * mix(4.1, 5.2, thirdRandom) + time + thirdRandom * PI * 2.0);

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
  float motionPhase = seededValue(6.0) * PI * 2.0;
  vec2 motion = vec2(sin(time + motionPhase), cos(time + motionPhase))
      * vec2(0.055, 0.040);
  vec2 movingPoint = uv * cells + motion;
  vec2 cell = floor(movingPoint);
  float random = seededHash(cell);
  float secondRandom = remix(random);
  vec2 point = fract(movingPoint) - 0.5;
  point += vec2(random - 0.5, secondRandom - 0.5) * 0.10;
  point.x *= uSize.x / max(uSize.y, 1.0) * cells.y / cells.x;

  float spinDirection = mix(-1.0, 1.0, step(0.5, secondRandom));
  float spinCount = mix(1.0, 2.0, step(0.78, random));
  float rotation = time * spinDirection * spinCount + random * PI * 2.0;
  float sine = sin(rotation);
  float cosine = cos(rotation);
  point = mat2(cosine, -sine, sine, cosine) * point;

  float radius = length(point);
  float fruitRadius = mix(0.215, 0.285, random);
  float rind = softLine(abs(radius - fruitRadius), 0.010, 0.020);
  float segmentDistance = min(
    abs(point.y),
    min(abs(point.y - point.x * 0.577), abs(point.y + point.x * 0.577))
  );
  float segments = softLine(segmentDistance, 0.004, 0.012)
      * (1.0 - smoothstep(fruitRadius - 0.055, fruitRadius, radius));
  float flesh = (1.0 - smoothstep(fruitRadius - 0.065, fruitRadius, radius)) * 0.32;
  float alpha = (rind * 0.105 + segments * 0.060 + flesh * 0.038);
  float alternate = step(0.52, secondRandom);
  vec3 fruitColor = mix(uPrimary.rgb, uTertiary.rgb, alternate * 0.62);
  finish(fruitColor * alpha, alpha);
}

void paintBotanical(vec2 uv, float time) {
  vec2 cells = vec2(3.0, 4.2);
  float motionPhase = seededValue(7.0) * PI * 2.0;
  vec2 motion = vec2(sin(time + motionPhase), cos(time + motionPhase))
      * vec2(0.035, 0.050);
  vec2 movingPoint = uv * cells + motion;
  vec2 cell = floor(movingPoint);
  float random = seededHash(cell + vec2(3.0, 11.0));
  float secondRandom = remix(random);
  vec2 point = fract(movingPoint) - 0.5;
  point += vec2(random - 0.5, secondRandom - 0.5) * 0.08;
  point.x *= uSize.x / max(uSize.y, 1.0) * cells.y / cells.x;

  float direction = mix(-0.88, 0.78, random);
  float sway = sin(time + secondRandom * PI * 2.0) * mix(0.065, 0.125, random);
  float sine = sin(direction + sway);
  float cosine = cos(direction + sway);
  point = mat2(cosine, -sine, sine, cosine) * point;

  // A tapered ellipse reads as a leaf while remaining cheap to evaluate.
  vec2 leafPoint = vec2(
    (point.x + 0.02) / mix(0.275, 0.350, random),
    point.y / mix(0.092, 0.132, secondRandom)
  );
  float taper = 1.0 + abs(leafPoint.x) * 0.70;
  float leafDistance = length(vec2(leafPoint.x, leafPoint.y * taper));
  float leaf = 1.0 - smoothstep(0.82, 1.0, leafDistance);
  float vein = softLine(abs(point.y), 0.003, 0.010)
      * (1.0 - smoothstep(0.04, 0.30, abs(point.x)));
  float alpha = leaf * 0.055 + vein * 0.085;
  float alternate = step(0.48, secondRandom);
  vec3 leafColor = mix(uPrimary.rgb, uTertiary.rgb, alternate * 0.70);
  finish(leafColor * alpha, alpha);
}

void paintNeon(vec2 uv, float time) {
  float gridRandom = seededValue(4.0);
  float horizontal = abs(
    fract((uv.y - uProgress * 0.125) * 8.0 + gridRandom) - 0.5
  );
  float diagonal = abs(
    fract((uv.x + uv.y * mix(0.16, 0.29, gridRandom) + uProgress / 7.0) * 7.0
      + gridRandom * 0.73) - 0.5
  );
  float horizontalGrid = softLine(horizontal, 0.010, 0.050) * 0.018
      + softLine(horizontal, 0.006, 0.012) * 0.050;
  float diagonalGrid = softLine(diagonal, 0.010, 0.050) * 0.018
      + softLine(diagonal, 0.006, 0.012) * 0.050;

  // Three independently shaped loops follow Lissajous-style paths. The first
  // pair periodically meets in the center before pulling apart, so overlapping
  // colors become part of the animation instead of a static tiled pattern.
  float orbit = time + seededValue(8.0) * PI * 2.0;
  vec2 firstCenter = vec2(
    0.50 + sin(orbit) * 0.27,
    0.47 + sin(orbit * 2.0) * 0.16
  );
  vec2 secondCenter = vec2(
    0.50 - sin(orbit) * 0.27,
    0.47 + sin(orbit * 2.0) * 0.16
  );
  vec2 thirdCenter = vec2(
    0.50 + cos(orbit) * 0.20,
    0.47 + sin(orbit * 3.0 + 1.1) * 0.24
  );

  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 firstPoint = uv - firstCenter;
  vec2 secondPoint = uv - secondCenter;
  vec2 thirdPoint = uv - thirdCenter;
  firstPoint.x *= aspect;
  secondPoint.x *= aspect;
  thirdPoint.x *= aspect;

  float firstAngle = atan(firstPoint.y, firstPoint.x);
  float secondAngle = atan(secondPoint.y, secondPoint.x);
  float thirdAngle = atan(thirdPoint.y, thirdPoint.x);
  float firstRadius = 0.120 * (1.0 + sin(firstAngle * 3.0 + orbit) * 0.16);
  float secondRadius = 0.100 * (1.0 + sin(secondAngle * 5.0 - orbit) * 0.18);
  float thirdRadius = 0.075 * (1.0 + sin(thirdAngle * 4.0 + orbit * 3.0) * 0.22);
  float firstDistance = abs(length(firstPoint) - firstRadius);
  float secondDistance = abs(length(secondPoint) - secondRadius);
  float thirdDistance = abs(length(thirdPoint) - thirdRadius);

  float firstLoop = softLine(firstDistance, 0.004, 0.010) * 0.175
      + softLine(firstDistance, 0.010, 0.050) * 0.050;
  float secondLoop = softLine(secondDistance, 0.004, 0.010) * 0.175
      + softLine(secondDistance, 0.010, 0.050) * 0.050;
  float thirdLoop = softLine(thirdDistance, 0.004, 0.009) * 0.190
      + softLine(thirdDistance, 0.009, 0.045) * 0.055;

  float alpha = horizontalGrid + diagonalGrid
      + firstLoop + secondLoop + thirdLoop;
  vec3 tint = uPrimary.rgb * (horizontalGrid + firstLoop)
      + uSecondary.rgb * (diagonalGrid + secondLoop)
      + uTertiary.rgb * thirdLoop;
  finish(tint, alpha);
}

void paintEditorial(vec2 uv, float time) {
  float motionPhase = seededValue(9.0) * PI * 2.0;
  float shiftedY = uv.y + sin(time + motionPhase) * 0.045;
  float ruleRow = floor(shiftedY * 10.0);
  float ruleRandom = seededHash(vec2(ruleRow, 37.0));
  float rules = softLine(abs(fract(shiftedY * 10.0) - 0.5), 0.006, 0.012)
      * step(mix(0.035, 0.12, ruleRandom), uv.x)
      * step(uv.x, mix(0.60, 0.96, ruleRandom));
  float marginRandom = seededValue(5.0);
  float margin = softLine(abs(uv.x - mix(0.09, 0.14, marginRandom)), 0.002, 0.006);

  vec2 blockGrid = vec2(uv.x * 2.0, shiftedY * 5.0);
  vec2 blockCellId = floor(blockGrid);
  float blockRandom = seededHash(blockCellId + vec2(47.0, 53.0));
  vec2 blockCell = fract(blockGrid) - 0.5;
  blockCell.x += (blockRandom - 0.5) * 0.12;
  float block = (1.0 - step(mix(0.18, 0.29, blockRandom), abs(blockCell.x)))
      * (1.0 - step(mix(0.075, 0.13, 1.0 - blockRandom), abs(blockCell.y)));
  float column = step(0.5, blockRandom);
  float alpha = rules * 0.050 + margin * 0.105 + block * 0.040;
  vec3 tint = uPrimary.rgb * (rules * 0.050 + block * 0.040)
      + mix(uPrimary.rgb, uTertiary.rgb, 0.78) * (margin * 0.105)
      + uTertiary.rgb * (block * column * 0.018);
  finish(tint, alpha);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  // Every time-dependent expression is periodic over this 0..2PI interval,
  // so AnimationController.repeat() can return to zero without a visual jump.
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
