Shader "Custom/BotWGrass"
{
    Properties
    {
		_BaseColor("Base Color", Color) = (1, 1, 1, 1)
		_TipColor("Tip Color", Color) = (1, 1, 1, 1)
		_BladeWidth("Blade Width", Float) = 0.05
    }
    SubShader
    {
        Tags 
		{ 
			"RenderType" = "Opaque" 
			"Queue" = "Geometry"
			"RenderPipeline" = "UniversalPipeline"
		}
        LOD 100
		Cull Off

		HLSLINCLUDE
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			CBUFFER_START(UnityPerMaterial)
				float4 _BaseColor;
				float4 _TipColor;
				float _BladeWidth;
			CBUFFER_END

			#define UNITY_TWO_PI 6.28318530718f

			struct VertexInput
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
			};

			struct VertexOutput
			{
				float4 vertex : SV_POSITION;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
			};

			struct GeomData
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			// Following functions from Roystan's code (https://github.com/IronWarrior/UnityGrassGeometryShader):

			// Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
			// Extended discussion on this function can be found at the following link:
			// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
			// Returns a number in the 0...1 range.
			float rand(float3 co)
			{
				return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
			}

			// Construct a rotation matrix that rotates around the provided axis, sourced from:
			// https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
			float3x3 AngleAxis3x3(float angle, float3 axis)
			{
				float c, s;
				sincos(angle, s, c);

				float t = 1 - c;
				float x = axis.x;
				float y = axis.y;
				float z = axis.z;

				return float3x3(
					t * x * x + c, t * x * y - s * z, t * x * z + s * y,
					t * x * y + s * z, t * y * y + c, t * y * z - s * x,
					t * x * z - s * y, t * y * z + s * x, t * z * z + c
				);
			}
		ENDHLSL

        Pass
        {
			Name "GrassPass"
			Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
			#pragma geometry geom
            #pragma fragment frag

            VertexOutput vert (VertexInput v)
            {
				VertexOutput o; 
				o.vertex = mul(unity_ObjectToWorld, v.vertex);// TransformObjectToHClip(v.vertex.xyz);
				o.normal = v.normal;
				o.tangent = v.tangent;
                return o;
            }

			GeomData TransformGeomToLocal(float3 pos, float3 offset, float3x3 transformationMatrix, float2 uv)
			{
				GeomData o;

				o.pos = TransformObjectToHClip(pos + mul(transformationMatrix, offset));
				o.uv = uv;

				return o;
			}

			[maxvertexcount(3)]
			void geom(triangle VertexOutput input[3], inout TriangleStream<GeomData> triStream)
			{
				float3 pos = input[0].vertex.xyz;

				float3 normal = input[0].normal;
				float4 tangent = input[0].tangent;
				float3 binormal = cross(normal, tangent) * tangent.w;

				float3x3 tangentToLocal = float3x3
				(
					tangent.x, binormal.x, normal.x,
					tangent.y, binormal.y, normal.y,
					tangent.z, binormal.z, normal.z
				);
				float3x3 randRotMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));
				float3x3 transformationMatrix = mul(tangentToLocal, randRotMatrix);

				float width = _BladeWidth;

				//o.pos = TransformObjectToHClip(pos + float3(0.05, 0, 0));
				triStream.Append(TransformGeomToLocal(pos, float3(width, 0, 0), transformationMatrix, float2(0, 0)));

				//o.pos = TransformObjectToHClip(pos + float3(-0.05, 0, 0));
				triStream.Append(TransformGeomToLocal(pos, float3(-width, 0, 0), transformationMatrix, float2(1, 0)));

				//o.pos = TransformObjectToHClip(pos + float3(0, 0.1, 0));
				triStream.Append(TransformGeomToLocal(pos, float3(0, 0, 0.1f), transformationMatrix, float2(0.5, 1)));

				//triStream.RestartStrip();
			}

            float4 frag (GeomData i) : SV_Target
            {
                return lerp(_BaseColor, _TipColor, i.uv.y);
            }
            ENDHLSL
        }
    }
}
