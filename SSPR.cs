
using UnityEngine;
using System;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

namespace SSPR
{
    [Serializable]
    internal class SSPRSettings
    {
        [SerializeField] internal int RTSize = 512;
        [SerializeField] internal float ReflectHeight = 0.2f;
        [SerializeField][Range(0.0f, 0.1f)] internal float StretchIntensity = 0.1f;
        [SerializeField][Range(0.0f, 1.0f)] internal float StretchThreshold = 0.3f;
        [SerializeField] internal float EdgeFadeOut = 0.6f;

        internal int GroupThreadX;
        internal int GroupThreadY;
        internal int GroupX;
        internal int GroupY;
    }

    [DisallowMultipleRendererFeature("SSPR")]
    public class SSPR : ScriptableRendererFeature
    {
        [SerializeField] private SSPRSettings mSettings = new SSPRSettings();

        private const string mComputeShaderName = "SSPR";

        private SSPRPass mRenderPass;
        private ComputeShader mComputeShader;

        

        public override void Create()
        {
            if(mRenderPass == null)
            {
                mRenderPass = new SSPRPass();
                mRenderPass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
            }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            // Debug.Log("SSPR: AddRenderPasses called! Frame: " + Time.frameCount);
            if (renderingData.cameraData.postProcessEnabled)
            {
                if (!GetComputeShaders())
                {
                    Debug.LogErrorFormat("{0}.AddRenderPasses(): Missing computeShader. {1} render pass will not be added.", GetType().Name, name);
                    return;
                }

                

                bool shouldAdd = mRenderPass.Setup(ref mSettings, ref mComputeShader);
                if (shouldAdd)
                {
                    renderer.EnqueuePass(mRenderPass);  
                }

            }
        }

        protected override void Dispose(bool disposing)
        {
            mRenderPass?.Dispose();
            mRenderPass = null;
        }

        private bool GetComputeShaders()
        {
            if(mComputeShader == null)
            {
                mComputeShader = (ComputeShader)Resources.Load(mComputeShaderName);
            }
            return mComputeShader != null;
        }

        class SSPRPass : ScriptableRenderPass
        {
            private SSPRSettings mSettings;
            private ComputeShader mComputeShader;
            private int mSSPRKernelID, mFillHoleKernelID;

            private string mSSPRKernelName = "SSPR";
            private string mFillHoleKernelName = "FillHole";

            private ProfilingSampler mProfilingSampler = new ProfilingSampler("SSPR");
            private RenderTextureDescriptor mSSPRReflectionDescriptor;

            private RTHandle mCameraColorTexture;
            private RTHandle mCameraDepthTexture;

            private static readonly int mReflectPlaneHeightID = Shader.PropertyToID("_ReflectionPlaneHeight"),
                mRTSizeID = Shader.PropertyToID("_SSPRReflectionSize"),
                mSSPRReflectionTextureID = Shader.PropertyToID("_SSPRReflectionTexture"),
                mCameraColorTextureID = Shader.PropertyToID("_CameraColorTexture"),
                mCameraDepthTextureID = Shader.PropertyToID("_CameraDepthTexture"),
                mSSPRHeightBufferID = Shader.PropertyToID("_SSPRHeightBuffer"),
                mCameraDirectionID = Shader.PropertyToID("_CameraDirection"),
                mStretchParamsID = Shader.PropertyToID("_StretchParams"),
                mEdgeFadeOutID = Shader.PropertyToID("_EdgeFadeOut"),
                mStretchThresholdID = Shader.PropertyToID("_StretchThreshold"),
                mStretchIntensityID = Shader.PropertyToID("_StretchIntensity");

            private const string mSSPRReflectionTextureName = "_SSPRReflectionTexture",
                mSSPRHeightTextureName = "_SSPRHeightBufferTexture";

            private RTHandle mSSPRReflectionTexture;
            private RTHandle mSSPRHeightTexture;



            internal SSPRPass()
            {
                mSettings = new SSPRSettings();
            }

            internal bool Setup(ref SSPRSettings featureSettings, ref ComputeShader computeShader)
            {
                mComputeShader = computeShader;
                mSettings = featureSettings;

                ConfigureInput(ScriptableRenderPassInput.Normal);
                return mComputeShader != null;
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 配置目标和清除
                var renderer = renderingData.cameraData.renderer;
                ConfigureTarget(renderer.cameraColorTargetHandle);
                ConfigureClear(ClearFlag.None, Color.white);
                mCameraColorTexture = renderer.cameraColorTargetHandle;
                mCameraDepthTexture = renderer.cameraDepthTargetHandle;

                float aspect = (float)Screen.width / Screen.height;
                // 计算线程组数量
                mSettings.GroupThreadX = 8;
                mSettings.GroupThreadY = 8;
                // 计算线程组线程
                mSettings.GroupY = Mathf.CeilToInt((float)mSettings.RTSize / mSettings.GroupThreadY);
                mSettings.GroupX = Mathf.CeilToInt(mSettings.GroupY * aspect);
                // 分配RTHandle
                mSSPRReflectionDescriptor = new RenderTextureDescriptor(mSettings.GroupThreadX * mSettings.GroupX, mSettings.GroupThreadY * mSettings.GroupY, RenderTextureFormat.BGRA32, 0, 0);
                mSSPRReflectionDescriptor.enableRandomWrite = true; // 开启uav随机读写
                RenderingUtils.ReAllocateIfNeeded(ref mSSPRReflectionTexture, mSSPRReflectionDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: mSSPRReflectionTextureName);



                // 只要r channel
                mSSPRReflectionDescriptor.colorFormat = RenderTextureFormat.RFloat;
                RenderingUtils.ReAllocateIfNeeded(ref mSSPRHeightTexture, mSSPRReflectionDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: mSSPRHeightTextureName);

                // 设置ComputeShader属性
                mSSPRKernelID = mComputeShader.FindKernel(mSSPRKernelName);


                mComputeShader.SetFloat(mReflectPlaneHeightID, mSettings.ReflectHeight);
                mComputeShader.SetFloat(mStretchThresholdID, mSettings.StretchThreshold);
                mComputeShader.SetFloat(mStretchIntensityID, mSettings.StretchIntensity);
                mComputeShader.SetVector(mRTSizeID, new Vector4(mSSPRReflectionDescriptor.width, mSSPRReflectionDescriptor.height, 1.0f / (float)mSSPRReflectionDescriptor.width, 1.0f / (float)mSSPRReflectionDescriptor.height));
                mComputeShader.SetTexture(mSSPRKernelID, mSSPRReflectionTextureID, mSSPRReflectionTexture);
                mComputeShader.SetTexture(mSSPRKernelID, mSSPRHeightBufferID, mSSPRHeightTexture);
                mComputeShader.SetTexture(mSSPRKernelID, mCameraColorTextureID, mCameraColorTexture);

                // Debug.Log("mCameraColorTexture is null? " + (mCameraColorTexture == null));
                // Debug.Log("mCameraColorTexture name: " + mCameraColorTexture?.name);

                mComputeShader.SetTexture(mSSPRKernelID, mCameraDepthTextureID, mCameraDepthTexture);
                mComputeShader.SetVector(mCameraDirectionID, renderingData.cameraData.camera.transform.forward);
                mComputeShader.SetVector(mStretchParamsID, new Vector4(mSettings.StretchIntensity, mSettings.StretchThreshold, 0.0f, 0.0f));
                mComputeShader.SetFloat(mEdgeFadeOutID, mSettings.EdgeFadeOut);

                mFillHoleKernelID = mComputeShader.FindKernel(mFillHoleKernelName);
                mComputeShader.SetTexture(mFillHoleKernelID, mSSPRReflectionTextureID, mSSPRReflectionTexture);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (mComputeShader == null)
                {
                    Debug.LogErrorFormat("{0}.Execute(): Missing computeShader. SSPR pass will not execute. Check for missing reference in the renderer resources.", GetType().Name);
                    return;
                }
                var cmd = CommandBufferPool.Get();
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                using(new ProfilingScope(cmd, mProfilingSampler))
                {
                    // Dispatch ComputeShader
                    cmd.DispatchCompute(mComputeShader, mSSPRKernelID, mSettings.GroupX, mSettings.GroupY, 1);
                    cmd.DispatchCompute(mComputeShader, mFillHoleKernelID, mSettings.GroupX / 2, mSettings.GroupY / 2, 1);

                    // 设置全局数据 让反射物采样
                    cmd.SetGlobalTexture(mSSPRReflectionTextureID, mSSPRReflectionTexture);
                    //if(mSkyboxTexture != null)
                    //{
                    //    cmd.SetGlobalTexture("_Skybox2D", mSkyboxTexture);
                    //}
                    cmd.SetGlobalVector(mRTSizeID, new Vector4(mSSPRReflectionDescriptor.width, mSSPRReflectionDescriptor.height, 1.0f / (float)mSSPRReflectionDescriptor.width, 1.0f / (float)mSSPRReflectionDescriptor.height));
                }

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                mCameraColorTexture = null;
            }

            public void Dispose()
            {
                // 释放RTHandle
                mSSPRReflectionTexture?.Release();
                mSSPRReflectionTexture = null;

                mSSPRHeightTexture?.Release();
                mSSPRHeightTexture = null;
            }
        }

    }
}

