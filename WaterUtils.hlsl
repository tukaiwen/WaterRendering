float Random(int seed)
{
	return frac(sin(dot(float2(seed, 2), float2(12.9898, 78.233)))) * 2 - 1;
}

float2 RotateVector2(float2 _vector, float _theta)
{
	float2x2 rotateM = float2x2(cos(_theta), -sin(_theta), sin(_theta), cos(_theta));
	float2 rotatedVector = mul(rotateM, _vector);
	return rotatedVector;
}

void GerstnerWave(float2 waveDir, float4 waveParam, float3 pos, inout float3 delta_pos, inout float3 delta_normal, inout float3 delta_tangent, inout float3 delta_bitangent, int _WaveNums)
{
	float steepness = waveParam.x; // 坡度
	float wavelength = waveParam.y; // 频率
	float speed = waveParam.z;      // 速度
	float amplify = waveParam.w;    // 振幅
	float2 d = normalize(waveDir);
	
	float w = 2 * 3.1415926 / wavelength;
	speed *= sqrt(9.8 / w);
	float f = w * (dot(d, pos.xz) - speed * _Time.y);
	float sinf = sin(f);
	float cosf = cos(f);

    float amplify_xz = steepness / w * amplify; // 特殊的振幅 防止错位

    delta_tangent += float3(
        -d.x * d.x * w * (amplify_xz * sinf),
        d.x * w * amplify * cosf,
        -d.y * d.x * w * (amplify_xz * sinf)
    );

    delta_bitangent += float3(
        -d.x * d.y * w * amplify_xz * sinf,
        d.y * w * amplify * cosf,
        -d.y * d.y * w * amplify_xz * sinf
    );

    delta_normal += float3(
        -d.x * amplify_xz * w * cosf,
        -amplify * w * sinf,
        -d.y * amplify_xz * w * cosf
    );

    delta_pos += float3(
        d.x * amplify_xz * cosf,
        amplify * sinf,
        d.y * amplify_xz * cosf
    );
}