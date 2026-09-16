import modules.common;

struct vs_input {
  [[vk::location(0)]] float2 pos;
  [[vk::location(1)]] float3 circ;
  [[vk::location(2)]] float4 color;
  [[vk::location(3)]] float flicker;
  [[vk::location(4)]] float shape;
};

struct vs_output {
  float4 clipspace : SV_Position;
  [[vk::location(0)]] float2 uv;
  [[vk::location(1)]] float4 color;
  [[vk::location(3)]] float flicker;
  [[vk::location(4)]] float shape;
};

[[vk::binding(0, 0)]] ConstantBuffer<Global> global;

vs_output vs_main(vs_input input) {
  vs_output output;

  float2 p = (input.pos - 0.5) * (input.circ.z * 2 + EDGE_SOFTNESS);
  float2 r = p + 0.5 * (input.circ.z + EDGE_SOFTNESS * 0.5);

  float2 hv = global.viewport * 0.5;
  float2 wp = r + input.circ.xy;
  float2 o = (wp - hv) / hv;

  output.clipspace = float4(o, 1);
  output.uv = input.pos;
  output.color = input.color;
  output.flicker = input.flicker;
  output.shape = input.shape;

  return output;
}

float regular_metric(float2 p, float sides, float rotation) {
  const float PI = 3.14159265359;
  float sector = 2.0 * PI / sides;
  float angle = atan2(p.y, p.x) + rotation;
  return cos(floor(0.5 + angle / sector) * sector - angle) * length(p) /
         cos(PI / sides);
}

float star_metric(float2 p) {
  const float PI = 3.14159265359;
  float angle = atan2(p.y, p.x);
  float phase = frac((angle + PI * 0.5) * (5.0 / (2.0 * PI)) + 0.5);
  float point = 1.0 - abs(phase * 2.0 - 1.0);
  float radius = lerp(0.23, 0.52, point);
  return length(p) * 0.5 / radius;
}

float shape_metric(float2 p, float shape) {
  if (shape < 1.5) return length(p);                   // circle or ring
  if (shape < 2.5) return star_metric(p);              // star
  if (shape < 3.5) return regular_metric(p, 3.0, 1.57079632679); // triangle
  if (shape < 4.5) return abs(p.x) + abs(p.y);         // diamond
  if (shape < 5.5) return regular_metric(p, 6.0, 0.0); // hexagon
  if (shape < 6.5) return max(abs(p.x), abs(p.y));     // square

  float angle = atan2(p.y, p.x);
  float radius = 0.42 + 0.09 * cos(angle * 6.0);
  return length(p) * 0.5 / radius;                     // flower
}

float4 fs_main(vs_output input) {
  float d = shape_metric(input.uv * 2 - 1, input.shape);
  float p = length(float2(ddx(d), ddy(d)));
  float f = lerp(0.45, 0.5, input.flicker);
  float a;
  if (input.shape >= 0.5 && input.shape < 1.5) {
    float outer = smoothstep(0.0, EDGE_SOFTNESS, (f * 1.08 - d) / p);
    float inner = smoothstep(0.0, EDGE_SOFTNESS, (f * 0.70 - d) / p);
    a = max(0.0, outer - inner);
  } else {
    a = smoothstep(0.0, EDGE_SOFTNESS, (f - d) / p) * 0.7;
  }

  float glow = input.shape >= 0.5 && input.shape < 1.5
      ? 0.0
      : max(0.0, f - d) * input.flicker;
  return float4(input.color.rgb + glow, input.color.a * a);
}
