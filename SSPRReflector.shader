Shader "Unlit/SSPRReflector"
{
    Properties
    {
        _NormalTex("Normal Texture", 2D) = "bump" {}
        _XSpeed("Time XSpeed", Range(0, 1)) = 1.0
        _YSpeed("Time YSpeed", Range(0, 1)) = 1.0
        _NormalScale("Normal Scale", Range(0, 1)) = 1.0
        _SpecularPow("Specular Power", Range(0, 1)) = 0.5
        _WaterSpecularColor("Water Specular Color", Color) = (1, 1, 1, 1)
        _Distortion("Distortion Strength", Range(0, 1)) = 0.1
        // _SkyColor("Sky Color", Color) = (1, 1, 1, 1)

        [Toggle(_)] _Is_NeedNoiseJump("FlowMap IsNeedNoiseJump", Float) = 1

        _OffsetNoiseTex("OffsetNoise", 2D) = "white" {}

        [Header(SSS)]
        [Space(10)]
        _SSSScale("SSS Scale", Range(0, 5)) = 1
        _SSSPow("SSS Pow", Range(0, 1)) = 0.5
        _SSSColor("SSS Color", Color) = (1, 1, 1, 1)
        _SSSDistortion("SSS Distortion", Range(0, 1)) = 0.5

        [Header(Shadow)]
        [Space(10)]
        _ShadowLevel("Shadow Level", Range(0, 1)) = 1

        [Header(Refract)]
        [Space(10)]
        _DepthLevel("Depth Level", Range(0.01, 0.3)) = 0.3
        _DepthPower("Depth Power", Range(0.1, 1)) = 0.3
        _RefractBaseColor("Refract Base Color", Color) = (1, 1, 1, 1)
        _RefractDepthScale("Refract Depth Scale", Range(0.001, 3)) = 1

        [Header(Gerstner Waves)]
        [Space(10)]
        [KeywordEnum(Gerstner, Simple)] _Animation("Water Animation Type", float) = 10
        _WaveSteepness("Wave Steepness", Range(0, 2)) = 1
        _WaveLength("Wave Length", Range(0, 50)) = 1
        _WaveSpeed("Wave Speed", Range(0, 5)) = 1
        _WaveAmplify("Wave Amplify", Range(0, 3)) = 1
        _WaveNums("Wave Nums", Range(4, 50)) = 4
        _WaveDirX("Wave Direction X", Int) = 1
        _WaveDirY("Wave Direction Y", Int) = 1
        _FlowNormalLevel("Flow Normal Level", Range(0, 1)) = 0

        [Header(Jakebi)]
        [Space(10)]
        _JakebiFoamLevel ("JakebiFoamLevel", Range(0.5,2)) = 1.0
        _SeaFoamTex ("SeaFoamTex", 2D) = "black" {}
        _SeaFoamStrength ("SeaFoamStrength", Range(0,10)) = 3
        _SeaFoamColor ("SeaFoamColor", Color) = (1,1,1,1)
    }
    
    SubShader
    {
        Tags {"RenderPipeline" = "UniversalPipeline" "Queue" = "Overlay"}

        Pass
        {
            Name "SSPR Reflector Pass"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Shaders/SSPRReflectorPass.hlsl"

            #pragma vertex SSPRReflectorPassVertex
            #pragma fragment SSPRReflectorPassFragment

            #pragma multi_compile _ _ANIMATION_GERSTNER
            
            ENDHLSL

        }
    }
}


