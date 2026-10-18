"""Beads at the size they are drawn (OM, 2026-10-18), iOS side.

The game atlas (beads, eyes, accessories) was sampled at LOD 0 only and never
got mipmaps, so a zoomed-out crowd read the full 3136 x 4032 atlas for every
bead. On Wyrm Android's Moto (Adreno 619) the frame probe measured the arena
pass at 5 ms with 250 beads and 21 ms with 1,900. The atlas now gets mip
levels 0..4 and its own sampler (`bead_sampler`) reads up to level 4: bead
cells are 448 px (7 x 64) and accessory cells 112 px (7 x 16), so a cell never
shares a texel with its neighbour on those levels. Same text as Wyrm Android's
tree (app/src/rendering/renderer.c, renderer.h, texture.c, texture.h); the
Android-only CPU chain for Mali is not needed on Apple GPUs. The Skin Studio
atlas (8 x 8 cells of 128 px, binding 4) is read through the same sampler.
"""
import sys
from pathlib import Path

SAMPLER = """      NULL, &r->atlas_sampler);

  /* Beads at the size they are drawn (OM, 2026-10-18). The game atlas was
     sampled at LOD 0 only, so every bead of a zoomed-out crowd read the full
     3136 x 4032 atlas: on the Moto (Adreno 619) the arena pass went from
     5 ms with 250 beads to 21 ms with 1,900 (frame probe), while the
     reference client mipmaps the same kind of atlas. The cells stay clean
     because they line up with every level used: bead cells are 448 px
     (7 x 64) and the accessory cells 112 px (7 x 16), so up to level 4 a
     cell never shares a texel with its neighbour (beads 28 px, accessories
     7 px there). Level 4 is also about the smallest a bead is drawn, so the
     cap costs nothing in speed. The small negative bias keeps near beads
     crisp; the bead shader masks each cell to its circle anyway. */
  vkCreateSampler(
      ctx->device,
      &(VkSamplerCreateInfo){.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                             .pNext = NULL,
                             .flags = 0,
                             .magFilter = VK_FILTER_LINEAR,
                             .minFilter = VK_FILTER_LINEAR,
                             .mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR,
                             .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                             .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                             .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                             .mipLodBias = BEAD_ATLAS_LOD_BIAS,
                             .minLod = 0.0f,
                             .maxLod = BEAD_ATLAS_MAX_LOD},
      NULL, &r->bead_sampler);
"""

BINDING_OLD = """                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo =
                    &(VkDescriptorImageInfo){
                        r->atlas_sampler, r->tex_atlas->view,"""

# Skin Studio's placeholder on binding 4 (the game atlas until one is worn).
PLACE_OLD = """                /* Skin Studio: the game atlas until one is worn (never
                   sampled then; a descriptor must point at something). */
                .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = NULL,
                .dstSet = r->global_set[i],
                .dstBinding = 4,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo =
                    &(VkDescriptorImageInfo){
                        r->atlas_sampler, r->tex_atlas->view,"""

PAIRS = {
    "app/src/rendering/texture.h": [
        ("texture* create_mipmap_texture(tcontext* ctx, const char* filename);\n",
         "/* The game atlas's sampler limits (renderer.c): levels 0..4 are clean. */\n"
         "#define BEAD_ATLAS_MAX_LOD 4.0f\n"
         "#define BEAD_ATLAS_LOD_BIAS (-0.25f)\n\n"
         "texture* create_mipmap_texture(tcontext* ctx, const char* filename);\n"),
    ],
    "app/src/rendering/texture.c": [
        ('  bool generate_mipmaps = strstr(filename, "tex_atlas") == NULL;\n',
         "  /* The game atlas is mipmapped too since 2026-10-18 (renderer.c\n"
         "     bead_sampler), but only the levels whose cells stay clean. */\n"
         '  const bool is_atlas = strstr(filename, "tex_atlas") != NULL;\n'
         "  bool generate_mipmaps = true;\n"),
        ("""  int mip_levels = generate_mipmaps
                       ? (uint32_t)(floorf(log2f(GLM_MAX(w, h))) + 1)
                       : 1;
""", """  int mip_levels = generate_mipmaps
                       ? (uint32_t)(floorf(log2f(GLM_MAX(w, h))) + 1)
                       : 1;
  if (is_atlas && mip_levels > (int)BEAD_ATLAS_MAX_LOD + 1)
    mip_levels = (int)BEAD_ATLAS_MAX_LOD + 1;
"""),
    ],
    "app/src/rendering/renderer.h": [
        ("  VkSampler atlas_sampler;\n",
         "  VkSampler atlas_sampler;\n"
         "  /* The game atlas (beads, eyes, accessories): mipmapped up to\n"
         "     BEAD_ATLAS_MAX_LOD. See renderer.c. */\n"
         "  VkSampler bead_sampler;\n"),
    ],
    "app/src/rendering/renderer.c": [
        ("      NULL, &r->atlas_sampler);\n", SAMPLER),
        (BINDING_OLD, BINDING_OLD.replace("r->atlas_sampler", "r->bead_sampler")),
        (PLACE_OLD, PLACE_OLD.replace("r->atlas_sampler", "r->bead_sampler")),
        ("""                  &(VkDescriptorImageInfo){r->atlas_sampler, tex->view,
                                           VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},""",
         """                  /* The Studio atlas is 8 x 8 cells of 128 px, clean
                     on every level the bead sampler reads (2026-10-18). */
                  &(VkDescriptorImageInfo){r->bead_sampler, tex->view,
                                           VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},"""),
        ("  vkDestroySampler(ctx->device, r->atlas_sampler, NULL);\n",
         "  vkDestroySampler(ctx->device, r->atlas_sampler, NULL);\n"
         "  vkDestroySampler(ctx->device, r->bead_sampler, NULL);\n"),
    ],
}


def apply(root, label="bead mips 2026-10-18", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
