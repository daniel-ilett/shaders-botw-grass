Shader "Custom/BotWGrass"
{
	Properties
	{
		//_GroundColor("Ground Color", Color) = (1, 1, 1, 1)
		_BaseColor("Base Color", Color) = (1, 1, 1, 1)
		_TipColor("Tip Color", Color) = (1, 1, 1, 1)
		_BladeTexture("Blade Texture", 2D) = "white" {}

		_BladeWidthMin("Blade Width (Min)", Range(0, 0.1)) = 0.02
		_BladeWidthMax("Blade Width (Max)", Range(0, 0.1)) = 0.05
		_BladeHeightMin("Blade Height (Min)", Range(0, 2)) = 0.1
		_BladeHeightMax("Blade Height (Max)", Range(0, 2)) = 0.2

		_BladeSegments("Blade Segments", Range(1, 10)) = 3
		_BladeBendDistance("Blade Forward Amount", Float) = 0.38
		_BladeBendCurve("Blade Curvature Amount", Range(1, 4)) = 2

		_BendDelta("Bend Variation", Range(0, 1)) = 0.2

		_TesselationFactor("Tesselation Subdivisions", Range(1, 32)) = 1

		_GrassMap("Grass Visibility Map", 2D) = "white" {}
		_GrassThreshold("Grass Visibility Threshold", Range(-0.1, 1)) = 0.5
		_GrassFalloff("Grass Visibility Fade-In Falloff", Range(0, 0.5)) = 0.05

		_WindMap("Wind Offset Map", 2D) = "bump" {}
		_WindVelocity("Wind Velocity", Vector) = (1, 0, 0, 0)
		_WindFrequency("Wind Pulse Frequency", Range(0, 1)) = 0.01
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
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _SHADOWS_SOFT

			#define UNITY_PI 3.14159265359f
			#define UNITY_TWO_PI 6.28318530718f
			#define BLADE_SEGMENTS 4
			
			CBUFFER_START(UnityPerMaterial)
				//float4 _GroundColor;
				sampler2D _BaseMap;

				float4 _BaseColor;
				float4 _TipColor;
				sampler2D _BladeTexture;

				float _BladeWidthMin;
				float _BladeWidthMax;
				float _BladeHeightMin;
				float _BladeHeightMax;

				float _BladeBendDistance;
				float _BladeBendCurve;

				float _BendDelta;

				float _TesselationFactor;
				
				sampler2D _GrassMap;
				float4 _GrassMap_ST;
				float  _GrassThreshold;
				float  _GrassFalloff;

				sampler2D _WindMap;
				float4 _WindMap_ST;
				float4 _WindVelocity;
				float  _WindFrequency;

				float4 _ShadowColor;
			CBUFFER_END

			struct VertexInput
			{
				float4 vertex  : POSITION;
				float3 normal  : NORMAL;
				float4 tangent : TANGENT;
				float2 uv      : TEXCOORD0;
			};

			struct VertexOutput
			{
				float4 vertex  : SV_POSITION;
				float3 normal  : NORMAL;
				float4 tangent : TANGENT;
				float2 uv      : TEXCOORD0;
			};

			struct TessellationFactors
			{
				float edge[3] : SV_TessFactor;
				float inside  : SV_InsideTessFactor;
			};

			struct GeomData
			{
				float4 pos : SV_POSITION;
				float2 uv  : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
			};

			// Following functions from Roystan's code:
			// (https://github.com/IronWarrior/UnityGrassGeometryShader)

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
			float3x3 angleAxis3x3(float angle, float3 axis)
			{
				float c, s;
				sincos(angle, s, c);

				float t = 1 - c;
				float x = axis.x;
				float y = axis.y;
				float z = axis.z;

				return float3x3
				(
					t * x * x + c, t * x * y - s * z, t * x * z + s * y,
					t * x * y + s * z, t * y * y + c, t * y * z - s * x,
					t * x * z - s * y, t * y * z + s * x, t * z * z + c
				);
			}

			// Regular vertex shader used by typical shaders.
			VertexOutput vert(VertexInput v)
			{
				VertexOutput o;
				o.vertex = TransformObjectToHClip(v.vertex.xyz);
				o.normal = v.normal;
				o.tangent = v.tangent;
				o.uv = TRANSFORM_TEX(v.uv, _GrassMap);
				return o;
			}

			// Vertex shader which just passes data to tessellation stage.
			VertexOutput tessVert(VertexInput v)
			{
				VertexOutput o;
				o.vertex = v.vertex;
				o.normal = v.normal;
				o.tangent = v.tangent;
				//o.uv = TRANSFORM_TEX(v.uv, _GrassMap);
				o.uv = v.uv;
				return o;
			}

			// Vertex shader which translates from object to world space.
			VertexOutput geomVert (VertexInput v)
            {
				VertexOutput o; 
				o.vertex = mul(unity_ObjectToWorld, v.vertex);
				o.normal = v.normal;
				o.tangent = v.tangent;
				o.uv = TRANSFORM_TEX(v.uv, _GrassMap);
                return o;
            }

			// Tesselation hull and domain shaders derived from Catlike Coding's tutorial:
			// https://catlikecoding.com/unity/tutorials/advanced-rendering/tessellation/

			// The patch constant function is where we create new control
			// points on the patch. For the edges, increasing the tessellation
			// factors adds new vertices on the edge. Increasing the inside
			// will add more 'layers' inside the new triangle.
			TessellationFactors patchConstantFunc(InputPatch<VertexInput, 3> patch)
			{
				TessellationFactors f;

				f.edge[0] = _TesselationFactor;
				f.edge[1] = _TesselationFactor;
				f.edge[2] = _TesselationFactor;
				f.inside = _TesselationFactor;

				return f;
			}

			// The hull function is the first half of the tesselation shader.
			// It operates on each patch (in our case, a patch is a triangle),
			// and outputs new control points for the other tessellation stages.
			//
			// The patch constant function is where we create new control points
			// (which are kind of like new vertices).
			[domain("tri")]
			[outputcontrolpoints(3)]
			[outputtopology("triangle_cw")]
			[partitioning("integer")]
			[patchconstantfunc("patchConstantFunc")]
			VertexInput hull(InputPatch<VertexInput, 3> patch, uint id : SV_OutputControlPointID)
			{
				return patch[id];
			}

			// In between the hull shader stage and the domain shader stage, the
			// tessellation stage takes place. This is where, under the hood,
			// the graphics pipeline actually generates the new vertices.

			// The domain function is the second half of the tessellation shader.
			// It interpolates the properties of the vertices (position, normal, etc.)
			// to create new vertices.
			[domain("tri")]
			VertexOutput domain(TessellationFactors factors, OutputPatch<VertexInput, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
			{
				VertexInput i;

				#define DOMAIN_INTERPOLATE(fieldname) i.fieldname = \
					patch[0].fieldname * barycentricCoordinates.x + \
					patch[1].fieldname * barycentricCoordinates.y + \
					patch[2].fieldname * barycentricCoordinates.z;

				DOMAIN_INTERPOLATE(vertex)
				DOMAIN_INTERPOLATE(normal)
				DOMAIN_INTERPOLATE(tangent)
				DOMAIN_INTERPOLATE(uv)

				return tessVert(i);
			}

			// Geometry functions derived from Roystan's tutorial:
			// https://roystan.net/articles/grass-shader.html

			// This function applies a transformation (during the geometry shader),
			// converting to clip space in the process.
			GeomData TransformGeomToLocal(float3 pos, float3 offset, float3x3 transformationMatrix, float2 uv)
			{
				GeomData o;

				o.pos = TransformObjectToHClip(pos + mul(transformationMatrix, offset));
				o.uv = uv;
				o.worldPos = TransformObjectToWorld(pos + mul(transformationMatrix, offset));

				return o;
			}

			/*
			GeomData CreateGrassVertex(float3 pos, float width, float height, float2 uv, float3x3 transformationMatrix)
			{
				float3 tangentPos = float3(width, 0, height);
				float3 localPos = pos + mul(transformationMatrix, tangentPos);

				return TransformGeomToLocal(localPos, uv);
			}
			*/

			// This is the geometry shader. For each vertex on the mesh, a leaf
			// blade is created by generating additional vertices.
			[maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
			void geom(point VertexOutput input[1], inout TriangleStream<GeomData> triStream)
			{
				float grassVisibility = tex2Dlod(_GrassMap, float4(input[0].uv, 0, 0)).x;

				if (grassVisibility >= _GrassThreshold)
				{
					float3 pos = input[0].vertex.xyz;

					float3 normal = input[0].normal;
					float4 tangent = input[0].tangent;
					float3 binormal = cross(normal, tangent.xyz) * tangent.w;

					float3x3 tangentToLocal = float3x3
					(
						tangent.x, binormal.x, normal.x,
						tangent.y, binormal.y, normal.y,
						tangent.z, binormal.z, normal.z
					);

					// Rotate around the y-axis a random amount.
					float3x3 randRotMatrix = angleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1.0f));

					// Rotate around the bottom of the blade a random amount.
					float3x3 randBendMatrix = angleAxis3x3(rand(pos.zzx) * _BendDelta * UNITY_PI * 0.5f, float3(-1.0f, 0, 0));

					float2 windUV = pos.xz * _WindMap_ST.xy + _WindMap_ST.zw + normalize(_WindVelocity.xzy) * _WindFrequency * _Time.y;
					float2 windSample = (tex2Dlod(_WindMap, float4(windUV, 0, 0)).xy * 2 - 1) * length(_WindVelocity);

					float3 windAxis = normalize(float3(windSample.x, windSample.y, 0));
					float3x3 windMatrix = angleAxis3x3(UNITY_PI * windSample, windAxis);



					//
					float3x3 baseTransformationMatrix = mul(tangentToLocal, randRotMatrix);
					float3x3 tipTransformationMatrix = mul(mul(mul(tangentToLocal, windMatrix), randBendMatrix), randRotMatrix);

					float falloff = smoothstep(_GrassThreshold, _GrassThreshold + _GrassFalloff, grassVisibility);
					float minWidth = falloff * _BladeWidthMin;
					float minHeight = falloff * _BladeHeightMin;

					float width  = lerp(_BladeWidthMin, _BladeWidthMax, rand(pos.xzy) * falloff);
					float height = lerp(_BladeHeightMin, _BladeHeightMax, rand(pos.zyx) * falloff);
					float forward = rand(pos.yyz) * _BladeBendDistance;

					// Create blade segments by adding two vertices at once.
					for (int i = 0; i < BLADE_SEGMENTS; ++i)
					{
						float t = i / (float)BLADE_SEGMENTS;
						float3 offset = float3(width * (1 - t), pow(t, _BladeBendCurve) * forward, height * t);

						float3x3 transformationMatrix = (i == 0) ? baseTransformationMatrix : tipTransformationMatrix;

						triStream.Append(TransformGeomToLocal(pos, float3( offset.x, offset.y, offset.z), transformationMatrix, float2(0, t)));
						triStream.Append(TransformGeomToLocal(pos, float3(-offset.x, offset.y, offset.z), transformationMatrix, float2(1, t)));
					}

					// Add the final vertex at the tip of the grass blade.
					triStream.Append(TransformGeomToLocal(pos, float3(0, forward, height), tipTransformationMatrix, float2(0.5, 1)));

					triStream.RestartStrip();
				}
			}
		ENDHLSL

		/*
		// This pass draws the ground beneath the grass, i.e. the original mesh.
		Pass
		{
			Name "GroundPass"
			Tags { "LightMode" = "UniversalForward" }

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			float4 frag(VertexOutput v) : SV_Target
			{
				return _GroundColor;
			}
			ENDHLSL
		}
		*/

		// This pass draws the grass blades generated by the geometry shader.
        Pass
        {
			Name "GrassPass"
			Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
			#pragma require geometry
			#pragma require tessellation tessHW

            #pragma vertex geomVert
			#pragma hull hull
			#pragma domain domain
			#pragma geometry geom
            #pragma fragment frag

            float4 frag (GeomData i) : SV_Target
            {
				float4 color = tex2D(_BladeTexture, i.uv);

#ifdef _MAIN_LIGHT_SHADOWS
				VertexPositionInputs vertexInput = (VertexPositionInputs)0;
				vertexInput.positionWS = i.worldPos;

				float4 shadowCoord = GetShadowCoord(vertexInput);
				half shadowAttenuation = saturate(MainLightRealtimeShadow(shadowCoord) + 0.25f);
				float4 shadowColor = lerp(0.0f, 1.0f, shadowAttenuation);
				color *= shadowColor;
#endif

                return color * lerp(_BaseColor, _TipColor, i.uv.y);
			}
			ENDHLSL
		}

		/*
		// Shadow-casting pass.
		Pass
		{
			Name "ShadowCaster"
			Tags { "LightMode" = "ShadowCaster" }

			ZWrite On
			ZTest LEqual

			HLSLPROGRAM
			#pragma require geometry
			#pragma require tessellation tessHW

			#pragma vertex geomVert
			#pragma hull hull
			#pragma domain domain
			#pragma geometry geom
			#pragma fragment frag
			#pragma multi_compile_shadowcaster

			float4 frag(GeomData i) : SV_Target
			{
				//SHADOW_CASTER_FRAGMENT(i)

				return 1;
			}
			ENDHLSL
		}
		*/
    }
}
