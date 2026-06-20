#pragma once

//============================================================================
//	NEMEngine public runtime API
//	ゲーム側はこの公開ヘッダとインポートライブラリだけでエディタを起動する
//	エンジンソースには依存させない、DLL境界はC-ABIで安定させる
//============================================================================

#ifdef _WIN32
#ifdef NEMENGINE_BUILD_DLL
#define NEMENGINE_RUNTIME_API extern "C" __declspec(dllexport)
#else
#define NEMENGINE_RUNTIME_API extern "C" __declspec(dllimport)
#endif
#else
#define NEMENGINE_RUNTIME_API extern "C"
#endif

// エディタを起動してアプリのリターンコードを返す
NEMENGINE_RUNTIME_API int NEM_RunEditor();
