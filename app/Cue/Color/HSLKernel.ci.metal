// app/Cue/Color/HSLKernel.ci.metal
#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
namespace coreimage {

// Helper: RGB → HSL (luminance) approximation in [0..1]
float3 rgb2hsl(float3 c) {
    float maxc = max(c.r, max(c.g, c.b));
    float minc = min(c.r, min(c.g, c.b));
    float l = (maxc + minc) * 0.5;
    float d = maxc - minc;
    float h = 0.0, s = 0.0;
    if (d > 1e-6) {
        s = l > 0.5 ? d / (2.0 - maxc - minc) : d / (maxc + minc);
        if (maxc == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
        else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
        else                  h = (c.r - c.g) / d + 4.0;
        h /= 6.0;
    }
    return float3(h, s, l);
}

float hue2rgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0/2.0) return q;
    if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
    return p;
}

float3 hsl2rgb(float3 hsl) {
    float h = hsl.x, s = hsl.y, l = hsl.z;
    if (s < 1e-6) return float3(l);
    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;
    return float3(
        hue2rgb(p, q, h + 1.0/3.0),
        hue2rgb(p, q, h),
        hue2rgb(p, q, h - 1.0/3.0)
    );
}

// 8 hue band centers (red, orange, yellow, green, aqua, blue, purple, magenta), normalized 0..1.
constant float bandCenters[8] = { 0.0, 0.0833, 0.1667, 0.3333, 0.5, 0.6667, 0.75, 0.8333 };

// Triangular weight for a single band on hue h.
float bandWeight(float h, int idx) {
    float c = bandCenters[idx];
    float d = abs(h - c);
    d = min(d, 1.0 - d);          // wrap
    float halfWidth = 1.0 / 16.0; // total = 8 bands, half-overlap at 1/16
    return clamp(1.0 - d / halfWidth, 0.0, 1.0);
}

// 24 floats: for each band, (hueShift[-1..1 = -180..180° but we use small 8.3% = ±30°],
// satMult, lumShift). We pass them as 8 packed float3 inside one float* buffer of size 24.
float4 hslAdjust(coreimage::sample_t pixel, float h0, float s0, float l0,
                 float h1, float s1, float l1,
                 float h2, float s2, float l2,
                 float h3, float s3, float l3,
                 float h4, float s4, float l4,
                 float h5, float s5, float l5,
                 float h6, float s6, float l6,
                 float h7, float s7, float l7) {
    float3 rgb = pixel.rgb;
    float3 hsl = rgb2hsl(rgb);

    float dh = 0, ds = 0, dl = 0;
    float h[8] = { h0, h1, h2, h3, h4, h5, h6, h7 };
    float s[8] = { s0, s1, s2, s3, s4, s5, s6, s7 };
    float l[8] = { l0, l1, l2, l3, l4, l5, l6, l7 };

    for (int i = 0; i < 8; i++) {
        float w = bandWeight(hsl.x, i);
        dh += w * h[i];
        ds += w * s[i];
        dl += w * l[i];
    }

    hsl.x = fract(hsl.x + dh);
    hsl.y = clamp(hsl.y * (1.0 + ds), 0.0, 1.0);
    hsl.z = clamp(hsl.z + dl, 0.0, 1.0);

    float3 outRgb = hsl2rgb(hsl);
    return float4(outRgb, pixel.a);
}

}
}
