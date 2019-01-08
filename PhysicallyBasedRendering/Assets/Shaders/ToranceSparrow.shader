Shader "MyShaders/TorranceSparrow"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
		_Color("Main Color", Color) = (1,1,1,1)
		_BumpMap("Normal Map", 2D) = "bump" {}
		_Roughness("Roughness", Range(0, 1.0)) = 0.5
		_Metallic("Metallic", Range(0, 1.0)) = 0.5
		_Reflectance("Reflectance", Range(0, 1.0)) = 0.5
	}
	SubShader
	{
		Tags { "RenderType" = "Opaque" "LightMode" = "ForwardBase"}

		LOD 100

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "Lighting.cginc"
			#include "UnityCG.cginc"
#include "UnityStandardBRDF.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 worldPos : TEXCOORD1;
				float3 tspace0 : TEXCOORD2;
				float3 tspace1 : TEXCOORD3;
				float3 tspace2 : TEXCOORD4;
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;
			half4 _Color;
			sampler2D _BumpMap;
			float _Roughness;
			float _Metallic;
			float _Reflectance;


			// 光学計算処理 ================================================
			
			// NDF GGX
			float D_GGX(float roughness, float NoH)
			{
				float a = NoH * roughness;
				float k = roughness / (1.0 - NoH * NoH + a * a);
				return k * k * (1.0 / UNITY_PI);
			}

			// NDF 最適化 GGX
			float D_OptGGX(float roughness, float NoH, const float3 n, const float3 h)
			{
				float3 NxH = cross(n, h);
				float a = NoH * roughness;
				float k = roughness / (dot(NxH, NxH) + a * a);
				return k * k*(1.0 / UNITY_PI);
			}

			// Visibility Term height-correlated SmithGGX
			float V_SmithGGXCorrelated(float NoV, float NoL, float roughness)
			{
				float r2 = roughness * roughness;
				float GGXV = NoL * sqrt(NoV * NoV * (1.0 - r2) + r2);
				float GGXL = NoV * sqrt(NoL * NoL * (1.0 - r2) + r2);
				return 0.5 / (GGXV + GGXL + 1e-5f);
			}

			// Visibility Term Fast height-correlated SmithGGX
			float V_SmithGGXCorrelatedFast(float NoV, float NoL, float roughness)
			{
				float r = roughness;
				float GGXV = NoL * (NoV * (1.0 - r) + r);
				float GGXL = NoV * (NoL * (1.0 - r) + r);
				return 0.5 / (GGXV + GGXL);
			}

			// f0値を取得する
			float3 Fresnel0(float reflectance, float metallic, float3 baseColor)
			{
				float3 dielectrics = (0.16 * reflectance * reflectance) * float3(1.0, 1.0, 1.0);
				return dielectrics * (1.0 - metallic) + (baseColor * metallic);
			}

			// Schlick近似式
			float3 F_Schlick(float VoH, float3 f0, float3 f90)
			{
				return f0 + ((f90 - f0) * pow(1.0 - VoH, 5.0));
			}

			// 最適化Schlick近似式
			float3 F_OptSchlick(float VoH, float3 f0)
			{
				float f = pow(1.0 - VoH, 5.0);
				return float3(f,f,f) + (f0 * (1.0 - f));
			}

			// ランバート拡散反射
			float Fd_Lambert()
			{
				return 1.0 / UNITY_PI;
			}

			// 頂点シェーダ =================================================
			v2f vert(appdata v)
			{
				v2f o;

				// ローカル空間の頂点位置からクリップ空間の位置へ変換します
				o.vertex = UnityObjectToClipPos(v.vertex);

				// uv座標を算出します
				// TRANSFORM_TEXはインスペクター上で入力されたスケールとオフセット値から
				// 適切なuvを計算してくれるマクロです
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);

				// ローカル空間の頂点位置からワールド空間の頂点位置へ変換します
				o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

				// ローカル空間法線をワールド空間に変換します
				float3 wNormal = UnityObjectToWorldNormal(v.normal);

				// ローカル空間接線をワールド空間に接線します
				float3 wTangent = UnityObjectToWorldDir(v.tangent.xyz);

				// ワールド空間での接線の向きを算出します
				// tangent.w には接線の向きを表す値です
				// 右手系・左手系座標の差異を吸収するため
				// 「unity_WorldTransformParams.w」（1.0 or -1.0）を乗算します
				float tangentSign = v.tangent.w * unity_WorldTransformParams.w;

				// 従接線を算出します
				// 従接線は、法線と接線の両方と直行するベクトルです
				// よって法線と接線の外積で求められます
				half3 wBitangent = cross(wNormal, wTangent) * tangentSign;

				// 接線マトリクスを作成します
				// この接線マトリクスはフラグメントシェーダーで法線マップと合わせて法線算出に使用されます
				o.tspace0 = half3(wTangent.x, wBitangent.x, wNormal.x);
				o.tspace1 = half3(wTangent.y, wBitangent.y, wNormal.y);
				o.tspace2 = half3(wTangent.z, wBitangent.z, wNormal.z);

				return o;
			}

			// フラグメントシェーダー ==========================================
			half4 frag(v2f i) : SV_Target
			{
				// アルベドカラーを算出します
				half4 albedo = tex2D(_MainTex, i.uv) * _Color;

				// 法線
				// Tangent空間上の法線を取得します
				float3 tnormal = UnpackNormal(tex2D(_BumpMap, i.uv));

				// 法線をTangent空間からワールド空間へ変換します
				float3 n;
				n.x = dot(i.tspace0, tnormal);
				n.y = dot(i.tspace1, tnormal);
				n.z = dot(i.tspace2, tnormal);
				n = normalize(n);

				// ライトの方向ベクトル
				float3 l = normalize(_WorldSpaceLightPos0.xyz);
				float NoL = saturate(dot(n, l));

				// 視線ベクトル
				float3 v = normalize(_WorldSpaceCameraPos);
				float NoV = abs(dot(n, v) + 1e-5);

				// ハーフベクトル
				float3 h = normalize(l + v);
				float NoH = saturate(dot(n, h));
				float VoH = saturate(dot(v, h));

				// 最終的に表現される色を算出します

				// Specular Term ============================================
				// NDF
				float D = D_OptGGX(_Roughness, NoH, n, h);
				
				// Visibility Term
				float V = V_SmithGGXCorrelatedFast(NoV, NoL, _Roughness);

				// Fresnel
				float3 f0 = Fresnel0(_Reflectance, _Metallic, albedo);
				float3 F = F_OptSchlick(VoH, f0);

				// とりあえずD項だけ表示
				//half4 col = half4(D, D, D, 1.0);

				// とりあえずV項だけ表示
				//half4 col = half4(V, V, V, 1.0);
				
				float3 specularTerm = D * V * F;


				// Diffuse Term ============================================
				float3 diffuseColor = (1.0 - _Metallic) * albedo.rgb;
				float3 diffuseTerm = Fd_Lambert() * diffuseColor;


				// Illuminance =============================================
				float3 illuminance = _LightColor0 * NoL;


				// 最終的な色を決定します。
				half3 col = (specularTerm + diffuseTerm) * illuminance;
				return half4(col, albedo.a);
			}
			ENDCG
		}
	}
}
