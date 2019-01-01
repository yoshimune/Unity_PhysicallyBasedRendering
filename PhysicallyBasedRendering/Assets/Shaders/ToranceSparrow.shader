Shader "MyShaders/TorranceSparrow"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
		_Color("Main Color", Color) = (1,1,1,1)
		_BumpMap("Normal Map", 2D) = "bump" {}
		_Roughness("Roughness", Range(0, 1.0)) = 0.5
		_Metallic("Metallic", Range(0, 1.0)) = 0.5
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

			inline float D_GGX(float roughness, float NoH)
			{
				float r2 = roughness * roughness;
				float NoH2 = NoH * NoH;
				float k = NoH2 * (r2 - 1.0) + 1.0;
				float k2 = k * k;
				return r2 / (UNITY_PI*k2);
			}

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

				// ライトの方向ベクトル
				float3 l = _WorldSpaceLightPos0.xyz;

				// 視線ベクトル
				float3 v = _WorldSpaceCameraPos;

				// ハーフベクトル
				float3 h = normalize(l + v);

				float NoH = saturate(dot(n, h));

				// 最終的に表現される色を算出します
				// とりあえずNDFを表示します
				float D = D_GGX(_Roughness, NoH);
				half4 col = half4(D,D,D,1.0);
				return col;
			}
			ENDCG
		}
	}
}
