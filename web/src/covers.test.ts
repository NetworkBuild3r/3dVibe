import { describe, expect, it } from "vitest";
import { cheapCoverUrl, coverVisual, fullCoverUrl } from "./covers";

const ready = {
  cover_status: "ready" as const,
  cover_url: "/covers/9.webp",
  cover_lqip_url: "/covers/9.lqip.webp",
  cover_placeholder: false
};

describe("cover LQIP bind", () => {
  it("prefers cover_lqip_url for cheap card chrome", () => {
    expect(cheapCoverUrl(ready)).toBe("/covers/9.lqip.webp");
    expect(fullCoverUrl(ready)).toBe("/covers/9.webp");
    expect(coverVisual(ready)).toBe("image");
  });

  it("falls back to cover_url when LQIP is absent", () => {
    const model = { ...ready, cover_lqip_url: null };
    expect(cheapCoverUrl(model)).toBe("/covers/9.webp");
    expect(fullCoverUrl(model)).toBe("/covers/9.webp");
  });

  it("treats LQIP-only ready as an image so cards can paint before the full webp", () => {
    const model = { ...ready, cover_url: null };
    expect(cheapCoverUrl(model)).toBe("/covers/9.lqip.webp");
    expect(coverVisual(model)).toBe("image");
  });
});
