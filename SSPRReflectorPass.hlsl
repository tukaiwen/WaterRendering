#ifndef _SSPRREFLECTOR_PASS_INCLUDED
#define _SSPRREFLECTOR_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl" 
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
#include "WaterUtils.hlsl"

struct Attributes {
	float4 positionOS : POSITION;
	float3 normalOS : NORMAL;
	float4 tangentOS : TANGENT;
	float2 uv : TEXCOORD0;
};

struct Varyings {
	float4 positionCS : SV_POSITION;
	//float4 positionNDC : TEXCOORD0;
	float3 positionWS : TEXCOORD1;
	float2 uv : TEXCOORD2;
	float3 normalWS : TEXCOORD3;
	float3 tangentWS : TEXCOORD4;
	float3 bitangentWS : TEXCOORD5;
	float4 screenPos : TEXCOORD6;
};

Texture2D<float4> _CameraDepthTexture;
SAMPLER(sampler_CameraDepthTexture);

TEXTURE2D(_OffsetNoiseTex);
SAMPLER(sampler_OffsetNoiseTex);
float4 _OffsetNoiseTex_ST;

TEXTURE2D(_SSPRReflectionTexture);
SAMPLER(sampler_SSPRReflectionTexture);

TEXTURE2D(_NormalTex);
SAMPLER(sampler_NormalTex);
float4 _NormalTex_ST;

half _Is_NeedNoiseJump;

// Shallow Water
float4 _ShallowWaterParams;
sampler2D _ShallowWaterHeightRT;

// Gerstner Waves
float _WaveSteepness;
float _WaveLength;
float _WaveSpeed;
int _WaveNums;
float _WaveAmplify;
int _WaveDirX;
int _WaveDirY;
float _FlowNormalLevel;

// 雅可比白沫
float _JakebiFoamLevel;     // 波峰白沫阈值
float _SeaFoamStrength;    // 白沫整体强度
float4 _SeaFoamTex_ST;     // 白沫纹理的Tiling/Offset
TEXTURE2D(_SeaFoamTex); 
half3 _SeaFoamColor;       // 白沫颜色

//float4 _SkyColor;
float _XSpeed;
float _YSpeed;
float _NormalScale;
float _SpecularPow;
float4 _WaterSpecularColor;
float _Distortion;
float _DepthLevel;
float _DepthPower;
float4 _RefractBaseColor;
float _RefractDepthScale;

float _ShadowLevel;
// SSS
float _SSSScale;
float _SSSPow;
float4 _SSSColor;
float _SSSDistortion;

Varyings SSPRReflectorPassVertex(Attributes input) {
	Varyings output;

	VertexPositionInputs vertexInputs = GetVertexPositionInputs(input.positionOS.xyz);
	output.positionCS = vertexInputs.positionCS;
	//output.positionNDC = vertexInputs.positionNDC;
	output.positionWS = vertexInputs.positionWS;

	VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
	output.normalWS = normalInputs.normalWS;
	output.tangentWS = normalInputs.tangentWS;
	output.bitangentWS = normalInputs.bitangentWS;

	output.uv = input.uv;
	output.screenPos = ComputeScreenPos(output.positionCS);

	// Gerstner 
#ifdef _ANIMATION_GERSTNER
	float3 wavePosWS, waveNormalWS, waveTangentWS, waveBitangentWS;
	wavePosWS = float3(0, 0, 0);
	waveNormalWS = float3(0, 1, 0);
	waveTangentWS = float3(1, 0, 0);
	waveBitangentWS = float3(0, 0, 1);
	float waveSteepness = _WaveSteepness / _WaveNums;
	for (int index = 0; index < _WaveNums; index++)
	{
		float waveLength = lerp(_WaveLength / 3, _WaveLength, (index + 1) / _WaveNums);
		float randSeed = Random(index + 1);
		float2 waveDir = normalize(float2(_WaveDirX, _WaveDirY));
		float2 rotatedWaveDir = RotateVector2(waveDir, randSeed * PI / 2);
		GerstnerWave(rotatedWaveDir, float4(waveSteepness, waveLength, _WaveSpeed, _WaveAmplify), output.positionWS, wavePosWS, waveNormalWS, waveTangentWS, waveBitangentWS, _WaveNums);
	}

	output.positionWS = float4(wavePosWS + output.positionWS.xyz, 1.0);
	output.positionCS = TransformWorldToHClip(output.positionWS.xyz);
	output.normalWS = normalize(waveNormalWS);
	output.tangentWS = normalize(waveTangentWS);
	output.bitangentWS = normalize(waveBitangentWS);

#endif

	// Shallow Water
	half2 offset = half2(1, 1);
#if SHADER_API_D3D11
	offset = half2(1, -1);
#endif
	float2 shallowUV = saturate(
		(output.positionWS.xz - _ShallowWaterParams.xy) * _ShallowWaterParams.w * offset
		+ float2(0.5, 0.5)
	);
	float heightValue = tex2Dlod(_ShallowWaterHeightRT, float4(shallowUV, 0, 0)).r;
	output.positionWS.y += heightValue * 1.0;
	output.positionCS = TransformWorldToHClip(output.positionWS.xyz);

	return output;
}

float3 FresnelSnhlick(float cosTheta, float3 F0)
{
	return F0 + pow(1.0 - cosTheta, 5);
}

struct custom_inputData
{
	float3 normalWS;
	float3 viewDirectionWS;
};

struct custom_surfaceData
{
	float smoothness;
	float specular;
};

half3 Simple_Specular_BRDF(custom_inputData input_data, custom_surfaceData surface_data, Light main_light)
{
	float NdotL = saturate(dot(input_data.normalWS, main_light.direction));
	float3 halfDir = normalize(main_light.direction + input_data.viewDirectionWS);
	float NdotH = saturate(dot(input_data.normalWS, halfDir));
	float NdotV = saturate(dot(input_data.normalWS, input_data.viewDirectionWS));

	half3 radiance = main_light.color * (main_light.distanceAttenuation * main_light.shadowAttenuation);

	float denominator = 4.0 * max(NdotL, 0.001) * max(NdotV, 0.001) + 0.0001;

	float d1 = (2.0 / (surface_data.smoothness * surface_data.smoothness + 0.000001)) - 2.0;
	float d2 = 1.0 / (PI * surface_data.smoothness * surface_data.smoothness + 0.000001);
	float D = d2 * pow(max(NdotH, 0.0), d1);

	float F = surface_data.specular + (1.0 - surface_data.specular) * pow(1.0 - saturate(dot(halfDir, input_data.viewDirectionWS)), 5.0);

	float g1 = surface_data.smoothness * 2.0 / PI;
	float gl = NdotL * (1.0 - g1) + g1;
	float gv = NdotV * (1.0 - g1) + g1;
	float G = 1.0 / (gl * gv + 1e-5f) * 0.25;

	float specular = D * F * G / denominator;

	half3 output = specular * radiance;
	return output;
}

half4 SSPRReflectorPassFragment(Varyings input) : SV_Target{

	// 测试一下噪声
	float noise = SAMPLE_TEXTURE2D(_OffsetNoiseTex, sampler_OffsetNoiseTex, input.uv).a;
	float time = _Time.y * _XSpeed * 0.1 + lerp(0, noise, _Is_NeedNoiseJump);

	// 计算法线扰动 以及法线扰动采样
	float2 distortedUV1 = input.uv + float2(time * 1.2, time * 0.7);
	float3 normal_var_1 = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, TRANSFORM_TEX(distortedUV1, _NormalTex)), _NormalScale).rgb;

	float2 distortedUV2 = input.uv - float2(time * 0.6, time * 0.9);
	float3 normal_var_2 = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, TRANSFORM_TEX(distortedUV2, _NormalTex)), _NormalScale).rgb;

	float3 normal_var = normalize(normal_var_1 + normal_var_2);

	float3x3 tangentTransform = float3x3(input.tangentWS, input.bitangentWS, input.normalWS);
	normal_var = normalize(mul(normal_var, tangentTransform));

	float2 offset = normal_var.xz * _Distortion * 0.3;

	float2 suv = ((input.screenPos.xy + offset) / input.screenPos.w);

	half4 reflection = SAMPLE_TEXTURE2D(_SSPRReflectionTexture, sampler_SSPRReflectionTexture, suv);

	float3 worldPos = input.positionWS;
	float3 viewDir = normalize(_WorldSpaceCameraPos - worldPos);

	// BRDF
	Light mainLight = GetMainLight();

	float3 lightDir = mainLight.direction;

	custom_inputData input_data;
	input_data.normalWS = normal_var;
	input_data.viewDirectionWS = viewDir;

	custom_surfaceData surface_data;
	surface_data.smoothness = lerp(0.01, 1.0, _SpecularPow);
	surface_data.specular = 0.5;

	half3 brdf = Simple_Specular_BRDF(input_data, surface_data, mainLight);
	brdf *= _WaterSpecularColor.rgb;
	
	// SSS
	float3 sss_H = normalize(lightDir + normal_var * _SSSDistortion);
	float sss_intensity = pow(saturate(dot(viewDir, -sss_H)), lerp(1, 5, _SSSPow)) * _SSSScale;
	float3 sss_color = _SSSColor * sss_intensity;

	//折射
	float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, input.screenPos.xy / input.screenPos.w);
	float depthValue = LinearEyeDepth(depth, _ZBufferParams);
	float depthWeight = pow(saturate((depthValue - input.screenPos.w) * _DepthLevel), _DepthPower);

	float3 refractTex = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, suv).rgb;
	refractTex = lerp(refractTex, _RefractBaseColor.rgb, depthWeight * _RefractDepthScale);
	
	half3 finalColor = 0;
	
	// Fresnel
	float NdotV = dot(normal_var, viewDir);
	float3 F = FresnelSnhlick(max(NdotV, 0.0), float3(0.02, 0.02, 0.02));
	finalColor += (1.0 - F) * (refractTex + sss_color);

	// SSPR反射无效时，fallback回天空盒反射
	if (dot(reflection.rgb, reflection.rgb) < 0.0001f) {
		float3 worldPos = input.positionWS;
		float3 viewDir = normalize(_WorldSpaceCameraPos - worldPos);
		float3 reflectDir = reflect(-viewDir, float3(0, 1, 0));
		
		half3 skyColor = GlossyEnvironmentReflection(reflectDir, 0.0, 1.0);
		finalColor += (skyColor + brdf) * F;
	}
	else
	{
		finalColor += (reflection.rgb + brdf) * F;
	}


	// 雅可比白沫
//#ifdef _ANIMATION_GERSTNER  
//	float jakb = input.tangentWS.x * input.bitangentWS.z - input.tangentWS.z * input.bitangentWS.x;
//	float waveFoam = saturate(-jakb + _JakebiFoamLevel);
//	//waveFoam *= (sin(_Time.y + noise * 10) * 0.5 + 0.5);  // 动态闪烁
//
//	float foamTex = SAMPLE_TEXTURE2D(_SeaFoamTex, sampler_LinearRepeat, input.uv * _SeaFoamTex_ST.xy + _SeaFoamTex_ST.zw).r;
//
//	finalColor += waveFoam * _SeaFoamStrength * foamTex * _SeaFoamColor.rgb;
//#endif


	finalColor = saturate(finalColor);
	return half4(finalColor, 1.0);
}

#endif