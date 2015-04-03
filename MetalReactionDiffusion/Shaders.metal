//
//  Shaders.metal
//  MetalReactionDiffusion
//
//  Created by Simon Gladman on 18/10/2014.
//  Copyright (c) 2014 Simon Gladman. All rights reserved.
//
// todo: https://code.google.com/p/reaction-diffusion/source/browse/trunk/Ready/Patterns/Yang2006/jumping.vti
// todo: https://www.youtube.com/watch?v=JhipxYrgNvI


#include <metal_stdlib>
using namespace metal;

struct ReactionDiffusionParameters
{
    // Fitzhugh-Nagumo
    
    float timestep;
    float a0;
    float a1;
    float epsilon;
    float delta;
    float k1;
    float k2;
    float k3;
    
    // Gray Scott
    
    float F;
    float K;
    float Du;
    float Dv;
    
    // Belousov
    
    float alpha;
    float beta;
    float gamma;
};

kernel void yolp_kernel(texture2d<float, access::read> inTexture [[texture(0)]],
                        texture2d<float, access::write> outTexture [[texture(1)]],
                        //constant ReactionDiffusionParameters &params [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    const uint2 northIndex(gid.x, gid.y - 1);
    const uint2 southIndex(gid.x, gid.y + 1);
    const uint2 westIndex(gid.x - 1, gid.y);
    const uint2 eastIndex(gid.x + 1, gid.y);

    const float4 northColor = inTexture.read(northIndex);
    const float4 southColor = inTexture.read(southIndex);
    const float4 westColor = inTexture.read(westIndex);
    const float4 eastColor = inTexture.read(eastIndex);

    float4 outColor1 = (northColor + southColor) / 2;
    const float4 outColor2(outColor1.r, outColor1.g, outColor1.b, 1.0);
    outTexture.write(outColor2, gid);
}


