import modules.common;

struct vs_input {
  [[vk::location(0)]] float2 pos;
  [[vk::location(1)]] float4 circ;
  [[vk::location(2)]] float4 uv;
  [[vk::location(3)]] float4 color;
  /* Hidden part (OM, 2026-10-30; game/redraw.c bead_cull_apply): xy the unit
     line to the bead above, z where its solid disc begins, w 1 when set. */
  [[vk::location(4)]] float4 clip;
};

struct vs_output {
  float4 clipspace : SV_Position;
  [[vk::location(0)]] float2 uv;
  [[vk::location(1)]] float2 uv2;
  [[vk::location(2)]] float4 color;
};

[[vk::binding(0, 0)]] ConstantBuffer<Global> global;
[[vk::binding(1, 0)]] Sampler2D tex_atlas;
/* Skin Studio (OM, 2026-10-12): the player's own atlas. */
[[vk::binding(4, 0)]] Sampler2D studio_tex;
/* AIR skin art (OM, 2026-11-08; game/wyrm_extras.c): wyrm_extras.png, read
   when the uv is shifted right by 8, drawn whole (no round bead mask). */
[[vk::binding(6, 0)]] Sampler2D extras_tex;

vs_output vs_main(vs_input input) {
  vs_output output;

  float half = 0.5 * (input.circ.z + EDGE_SOFTNESS);
  float2 centre = input.circ.xy + 0.5 * (input.circ.z + EDGE_SOFTNESS * 0.5);

  float s = sin(input.circ.w);
  float c = cos(input.circ.w);

  float2 off;
  float2 q;
  if (input.clip.w > 0.5) {
    /* Only the part the bead above leaves open: t from the far rim to
       clip.z along the line to it, the whole width across. q is the same
       point in the bead's own frame, so texture and rim are unchanged. */
    float2 u = input.clip.xy;
    float2 v = float2(-u.y, u.x);
    float t = lerp(-half, min(input.clip.z, half), input.pos.x);
    float n = lerp(-half, half, input.pos.y);
    off = u * t + v * n;
    float2 local = float2(off.x * c + off.y * s, -off.x * s + off.y * c);
    q = local / (2.0 * half) + 0.5;
  } else {
    float2 p = (input.pos - 0.5) * (input.circ.z + EDGE_SOFTNESS);
    off = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    q = input.pos;
  }

  float2 hv = global.viewport * 0.5;
  float2 wp = centre + off;
  float2 o = (wp - hv) / hv;

  output.clipspace = float4(o, 1);
  output.uv = q;
  output.uv2 = input.uv.xy + q * input.uv.zw;
  output.color = input.color;

  return output;
}

float4 fs_main(vs_output input) {
  /* A uv shifted right by 4 samples the Studio atlas (game/studio.h).
     Plain Sample, as before the Studio and as the reference client (OM,
     2026-10-13, Android FPS): this shader draws every bead of every snake,
     and the explicit-gradient SampleGrad of 7.1.3 cost it on phones. The
     branch is the same for a whole 2x2 quad (one bead sprite reads one
     atlas; its uv is >= 4 or <= 1), so the implicit mip choice stays
     defined. */
  float2 uv = input.uv2;
  [branch]
  if (uv.x >= 7.0)
    return input.color * extras_tex.Sample(uv - float2(8.0, 0.0)).rgba;
  /* Skin textures (OM, 2026-10-25, NTL's set; game/redraw.c
     skin_texture_apply): a uv of -1, -2 or -3 asks for a plain bead in its
     colour: round, square (turned with the bead for stripes, upright for
     squares), or NTL's soft shaded ball. No atlas read at all. */
  [branch]
  if (uv.x < -0.5) {
    float kind = -uv.x;
    float2 q = 2 * input.uv - 1;
    if (kind > 1.5 && kind < 2.5) {
      float m = max(abs(q.x), abs(q.y));
      float pm = length(float2(ddx(m), ddy(m)));
      float sa = smoothstep(0.0, EDGE_SOFTNESS, (1 - m) / pm);
      return float4(input.color.rgb, input.color.a * sa);
    }
    float pd = length(q);
    float pp = length(float2(ddx(pd), ddy(pd)));
    float pa = smoothstep(0.0, EDGE_SOFTNESS, (1 - pd) / pp);
    if (kind < 1.5) return float4(input.color.rgb, input.color.a * pa);
    float3 base = input.color.rgb;
    /* The five of 2026-10-26, all upright with the light at the top left. */
    if (kind > 8.5) {
      // Metal: brushed bands across the bead and one bright stripe.
      float band = 0.62 + 0.38 * cos(q.y * 3.4 + 0.7);
      float stripe = pow(saturate(1 - abs(q.y + 0.38) * 3.2), 2);
      float3 metal = base * band + 0.3 * stripe;
      metal *= lerp(1.0, 0.7, smoothstep(0.8, 1.0, pd));
      return float4(saturate(metal), input.color.a * pa);
    }
    if (kind > 7.5) {
      // Pearl: a soft pale sheen with a wide light.
      float hlp = saturate(1 - length(q - float2(-0.3, -0.36)) / 1.3);
      float3 pearl = lerp(base, float3(1, 1, 1), 0.3) * (0.78 + 0.32 * hlp) + 0.1 * (1 - pd);
      return float4(saturate(pearl), input.color.a * pa);
    }
    if (kind > 6.5) {
      // Neon: a dark core in a bright ring of the bead's colour.
      float ring = smoothstep(0.5, 0.66, pd) * (1 - smoothstep(0.9, 1.0, pd));
      float3 neon = lerp(base * 0.22, saturate(base * 1.6 + 0.12), ring);
      return float4(saturate(neon), input.color.a * pa);
    }
    if (kind > 5.5) {
      // Matte: flat, lit a little from above, a soft darker rim.
      float3 matte = base * lerp(1.08, 0.9, q.y * 0.5 + 0.5) * (1 - 0.3 * smoothstep(0.55, 1.0, pd));
      return float4(saturate(matte), input.color.a * pa);
    }
    if (kind > 4.5) {
      // Glossy: a lit ball with a sharp white spot.
      float hlg = saturate(1 - length(q - float2(-0.3, -0.34)) / 1.15);
      float spot = pow(saturate(1 - length(q - float2(-0.36, -0.44)) / 0.42), 3);
      float3 glossy = base * (0.58 + 0.5 * hlg) + 0.85 * spot;
      glossy *= lerp(1.0, 0.78, smoothstep(0.75, 1.0, pd));
      return float4(saturate(glossy), input.color.a * pa);
    }
    float hl = saturate(1 - length(q - float2(-0.3, -0.34)) / 1.15);
    float3 ball = input.color.rgb * (0.6 + 0.55 * hl * hl) + 0.16 * hl * hl * hl * hl;
    ball *= lerp(1.0, 0.8, smoothstep(0.72, 1.0, pd));
    return float4(saturate(ball), input.color.a * pa);
  }
  float4 c;
  [branch]
  if (uv.x >= 3.0)
    c = studio_tex.Sample(uv - float2(4.0, 0.0)).rgba;
  else
    c = tex_atlas.Sample(uv).rgba;
  float d = length(2 * input.uv - 1);
  float p = length(float2(ddx(d), ddy(d)));
  float a = smoothstep(0.0, EDGE_SOFTNESS, (1 - d) / p);
  return input.color * float4(c.rgb, a * c.a);
}