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
  // Horizontal and vertical circuit traces each occupy irregular positions
  // inside a coarse cell. Every trace has one animated right-angle bend; the
  // two families meet at junctions that receive a brighter shared halo.
  float seedPhase = seededValue(8.0) * PI * 2.0;
  float rowCoordinate = uv.y * 8.0;
  float row = floor(rowCoordinate);
  float rowPosition = fract(rowCoordinate);
  float rowRandom = seededHash(vec2(row, 31.0));
  float rowSecond = remix(rowRandom);
  float rowThird = remix(rowSecond);
  float rowCenter = 0.50 + (rowRandom - 0.5) * 0.42
      + sin(time + rowRandom * PI * 2.0 + seedPhase) * 0.055;
  float rowDirection = mix(-1.0, 1.0, step(0.5, rowSecond));
  float rowStep = mix(0.16, 0.32, rowThird) * rowDirection;
  float rowBefore = rowCenter - rowStep * 0.5;
  float rowAfter = rowCenter + rowStep * 0.5;
  float rowBend = 0.18 + rowThird * 0.64
      + sin(time + rowSecond * PI * 2.0) * 0.055;
  float rowLevel = mix(rowBefore, rowAfter, step(rowBend, uv.x));
  float omittedRow = floor(seededValue(4.0) * 5.0);
  float rowPresence = step(0.5, abs(mod(row, 5.0) - omittedRow));
  float rowSpan = step(min(rowBefore, rowAfter), rowPosition)
      * step(rowPosition, max(rowBefore, rowAfter));
  float horizontalCore = max(
    softLine(abs(rowPosition - rowLevel), 0.006, 0.018),
    softLine(abs(uv.x - rowBend), 0.0015, 0.0040) * rowSpan
  ) * rowPresence;
  float horizontalHalo = max(
    softLine(abs(rowPosition - rowLevel), 0.016, 0.060),
    softLine(abs(uv.x - rowBend), 0.0040, 0.0120) * rowSpan
  ) * rowPresence;

  float columnCoordinate = uv.x * 5.0;
  float column = floor(columnCoordinate);
  float columnPosition = fract(columnCoordinate);
  float columnRandom = seededHash(vec2(column, 73.0));
  float columnSecond = remix(columnRandom);
  float columnThird = remix(columnSecond);
  float columnCenter = 0.50 + (columnRandom - 0.5) * 0.42
      + cos(time + columnRandom * PI * 2.0 + seedPhase) * 0.055;
  float columnDirection = mix(-1.0, 1.0, step(0.5, columnSecond));
  float columnStep = mix(0.16, 0.32, columnThird) * columnDirection;
  float columnBefore = columnCenter - columnStep * 0.5;
  float columnAfter = columnCenter + columnStep * 0.5;
  float columnBend = 0.16 + columnThird * 0.68
      + cos(time + columnSecond * PI * 2.0) * 0.055;
  float columnLevel = mix(columnBefore, columnAfter, step(columnBend, uv.y));
  float omittedColumn = floor(seededValue(5.0) * 5.0);
  float columnPresence = step(
    0.5,
    abs(mod(column, 5.0) - omittedColumn)
  );
  float columnSpan = step(min(columnBefore, columnAfter), columnPosition)
      * step(columnPosition, max(columnBefore, columnAfter));
  float verticalCore = max(
    softLine(abs(columnPosition - columnLevel), 0.006, 0.018),
    softLine(abs(uv.y - columnBend), 0.0015, 0.0040) * columnSpan
  ) * columnPresence;
  float verticalHalo = max(
    softLine(abs(columnPosition - columnLevel), 0.016, 0.060),
    softLine(abs(uv.y - columnBend), 0.0040, 0.0120) * columnSpan
  ) * columnPresence;

  float horizontalLines = horizontalCore * 0.072 + horizontalHalo * 0.018;
  float verticalLines = verticalCore * 0.072 + verticalHalo * 0.018;
  float crossingCore = horizontalCore * verticalCore;
  float crossingHalo = horizontalHalo * verticalHalo;
  float crossings = crossingCore * 0.190 + crossingHalo * 0.080;

  float alpha = horizontalLines + verticalLines + crossings;
  vec3 tint = uPrimary.rgb * horizontalLines
      + uSecondary.rgb * verticalLines
      + uTertiary.rgb * crossings;
  finish(tint, alpha);
}

void paintEditorial(vec2 uv, float time) {
  // Editorial uses a typesetter-like system: consistent baselines, a fixed
  // margin rule, and a quiet dot matrix. No randomly sized content blocks.
  vec2 gridSize = vec2(8.0, 12.0);
  vec2 gridPoint = uv * gridSize;
  vec2 local = abs(fract(gridPoint) - 0.5);
  float rule = softLine(local.y, 0.004, 0.012)
      * step(0.07, uv.x) * step(uv.x, 0.94);
  float majorRule = 1.0 - step(
    0.5,
    mod(floor(gridPoint.y), 4.0)
  );
  float rules = rule * (0.040 + majorRule * 0.025);
  float margin = softLine(abs(uv.x - 0.105), 0.002, 0.006) * 0.095;

  vec2 dotPoint = local;
  dotPoint.x *= uSize.x / max(uSize.y, 1.0) * gridSize.y / gridSize.x;
  float dot = 1.0 - smoothstep(0.026, 0.070, length(dotPoint));
  float dotPattern = 1.0 - step(
    0.5,
    mod(floor(gridPoint.x) + floor(gridPoint.y), 4.0)
  );
  float pulse = 0.86 + sin(time) * 0.14;
  float dots = dot * (0.025 + dotPattern * 0.065 * pulse)
      * step(0.16, uv.x) * step(uv.x, 0.92);

  float alpha = rules + margin + dots;
  vec3 tint = uPrimary.rgb * rules
      + mix(uPrimary.rgb, uTertiary.rgb, 0.72) * margin
      + uTertiary.rgb * dots;
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
