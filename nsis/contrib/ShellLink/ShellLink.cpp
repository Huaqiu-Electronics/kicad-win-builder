/*
Module : ShellLink.cpp
Purpose: NSIS Plug-in for retriving shell link information
Created: 12/16/2003
Last Update: 01/14/2004

Copyright (c) 2004 Angelo Mandato.
See ShellLink.html for more information


Modified: 21/09/2005
Author:   Shengalts Aleksander aka Instructor (Shengalts@mail.ru)
Changes:  -code has been rewritten
          -added functions to change shell link information
          -reduced dll size 44Kb -> 4Kb
*/

//  Uncomment for debugging message boxes
//#define SHELLLINK_DEBUG

#include <windows.h>
#include <shlobj.h>
#include <propvarutil.h>
#include <propkey.h>

#define xatoi
//#include "ConvFunc.h"

#ifdef UNICODE
#include "nsis_unicode\pluginapi.h"
#else
#include "nsis_ansi\pluginapi.h"
#endif

#define NSISFUNC(name) extern "C" void __declspec(dllexport) name(HWND hWndParent, int string_size, TCHAR* variables, stack_t** stacktop, extra_parameters* extra)

#define SHELLLINKTYPE_GETARGS 1
#define SHELLLINKTYPE_GETDESC 2
#define SHELLLINKTYPE_GETHOTKEY 3
#define SHELLLINKTYPE_GETICONLOC 4
#define SHELLLINKTYPE_GETICONINDEX 5
#define SHELLLINKTYPE_GETPATH 6
#define SHELLLINKTYPE_GETSHOWMODE 7
#define SHELLLINKTYPE_GETWORKINGDIR 8
#define SHELLLINKTYPE_SETARGS 9
#define SHELLLINKTYPE_SETDESC 10
#define SHELLLINKTYPE_SETHOTKEY 11
#define SHELLLINKTYPE_SETICONLOC 12
#define SHELLLINKTYPE_SETICONINDEX 13
#define SHELLLINKTYPE_SETPATH 14
#define SHELLLINKTYPE_SETSHOWMODE 15
#define SHELLLINKTYPE_SETWORKINGDIR 16
#define SHELLLINKTYPE_SETRUNASADMIN 17
#define SHELLLINKTYPE_SETAPPMODELID 18

void ShortCutData(int nType);

//Get
NSISFUNC(GetShortCutArgs)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETARGS);
}

NSISFUNC(GetShortCutDescription)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETDESC);
}

NSISFUNC(GetShortCutHotkey)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETHOTKEY);
}

NSISFUNC(GetShortCutIconLocation)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETICONLOC);
}

NSISFUNC(GetShortCutIconIndex)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETICONINDEX);
}

NSISFUNC(GetShortCutTarget)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETPATH);
}

NSISFUNC(GetShortCutShowMode)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETSHOWMODE);
}

NSISFUNC(GetShortCutWorkingDirectory)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_GETWORKINGDIR);
}

//Set
NSISFUNC(SetShortCutArgs)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETARGS);
}

NSISFUNC(SetShortCutDescription)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETDESC);
}

NSISFUNC(SetShortCutHotkey)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETHOTKEY);
}

NSISFUNC(SetShortCutIconLocation)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETICONLOC);
}

NSISFUNC(SetShortCutIconIndex)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETICONINDEX);
}

NSISFUNC(SetShortCutTarget)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETPATH);
}

NSISFUNC(SetShortCutShowMode)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETSHOWMODE);
}

NSISFUNC(SetShortCutWorkingDirectory)
{
  EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETWORKINGDIR);
}

NSISFUNC(SetRunAsAdministrator)
{
	EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETRUNASADMIN);
}

NSISFUNC(SetAppModelId)
{
	EXDLL_INIT();
	ShortCutData(SHELLLINKTYPE_SETAPPMODELID);
}

errno_t local_memcpy_s(void* dest, rsize_t destsz, const void* src, rsize_t count)
{
	if (dest == NULL) {
		return EINVAL;
	}
	if (src == NULL) {
		return EINVAL;
	}

	if (count > destsz) {
		return ERANGE;
	}

	char* d = (char*)dest;
	const char* s = (const char*)src;

	for (rsize_t i = 0; i < count; ++i) {
		d[i] = s[i];
	}
	return 0;
}

void* local_memset(void* s, int c, size_t n) {
	unsigned char* p = (unsigned char*)s;

	unsigned char val = (unsigned char)c;

	for (size_t i = 0; i < n; ++i) {
		p[i] = val;
	}

	return s;
}

inline void LocalPropVariantInit(_Out_ PROPVARIANT* pvar)
{
	local_memset(pvar, 0, sizeof(PROPVARIANT));
}

size_t local_wcslen(const wchar_t* s) {
	size_t length = 0; // Initialize a counter for the length

	// Loop through the wide characters until the null wide terminator (L'\0') is found.
	// The loop condition *s++ checks the current wide character and then advances the pointer.
	while (*s != L'\0') {
		length++; // Increment the length for each non-null wide character
		s++;      // Move to the next wide character
	}

	return length; // Return the total count
}

inline HRESULT LocalInitPropVariantFromString(_In_ PCWSTR psz, _Out_ PROPVARIANT* ppropvar)
{
	HRESULT hr = psz != nullptr ? S_OK : E_INVALIDARG; // Previous API behavior counter to the SAL requirement.
	if (SUCCEEDED(hr))
	{
		SIZE_T const byteCount = static_cast<SIZE_T>((local_wcslen(psz) + 1) * sizeof(*psz));
		V_UNION(ppropvar, pwszVal) = static_cast<PWSTR>(CoTaskMemAlloc(byteCount));
		hr = V_UNION(ppropvar, pwszVal) ? S_OK : E_OUTOFMEMORY;
		if (SUCCEEDED(hr))
		{
			local_memcpy_s(V_UNION(ppropvar, pwszVal), byteCount, psz, byteCount);
			V_VT(ppropvar) = VT_LPWSTR;
		}
	}
	if (FAILED(hr))
	{
		LocalPropVariantInit(ppropvar);
	}
	return hr;
}


void ShortCutData(int nType)
{
	HRESULT hRes;
	IShellLink* psl;
	IPersistFile* ppf;
	IPropertyStore* pps = nullptr;

	int nBuf;
	WORD wHotkey;
	TCHAR* szBuf = (TCHAR*)LocalAlloc(LPTR, sizeof(TCHAR)*MAX_PATH);
	TCHAR* szBuf2 = (TCHAR*)LocalAlloc(LPTR, sizeof(TCHAR)*MAX_PATH);

	if( szBuf == NULL || szBuf2 == NULL )
	{
		if( szBuf )
			LocalFree(szBuf);
		if( szBuf2 )
			LocalFree(szBuf2);
		pushstring(TEXT("-1"));
		return;
	}

	popstring(szBuf);
	if (local_wcslen(szBuf) < 5)	// 5 is one of the smallest valid paths and still not even really valid
	{
		pushstring(TEXT("-1"));
		return;
	}

	if (nType > SHELLLINKTYPE_GETWORKINGDIR)
		popstring(szBuf2);

	hRes=CoCreateInstance(CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, IID_IShellLink, (LPVOID*) &psl);
	if (hRes == S_OK)
	{
		hRes=psl->QueryInterface(IID_IPersistFile, (LPVOID*) &ppf);
		if (hRes == S_OK)
		{
#ifdef UNICODE
			hRes=ppf->Load(szBuf, STGM_READWRITE);
#else
      WCHAR* wszPath = (WCHAR*)LocalAlloc(LPTR, sizeof(WCHAR)*MAX_PATH);
			MultiByteToWideChar(CP_ACP, 0, szBuf, -1, wszPath, MAX_PATH);
			hRes=ppf->Load(wszPath, STGM_READWRITE);
      LocalFree(wszPath);
#endif
			if (hRes == S_OK)
			{
				if (nType <= SHELLLINKTYPE_GETWORKINGDIR)
				{
					//Get
					switch(nType)
					{
						case SHELLLINKTYPE_GETARGS:
						{
							hRes=psl->GetArguments(szBuf, MAX_PATH);
							if (hRes != S_OK) szBuf[0]='\0';
						}; break;
						case SHELLLINKTYPE_GETDESC:
						{
							hRes=psl->GetDescription(szBuf, MAX_PATH);
							if (hRes != S_OK) szBuf[0]='\0';
						}; break;
						case SHELLLINKTYPE_GETHOTKEY:
						{
							hRes=psl->GetHotkey(&wHotkey);
							if (hRes == S_OK) wsprintf(szBuf, TEXT("%d"), wHotkey);
							else szBuf[0]='\0';
						}; break;
						case SHELLLINKTYPE_GETICONLOC:
						{
							hRes=psl->GetIconLocation(szBuf, MAX_PATH, &nBuf);
							if (hRes != S_OK) szBuf[0]='\0';
						}; break;
						case SHELLLINKTYPE_GETICONINDEX:
						{
							hRes=psl->GetIconLocation(szBuf, MAX_PATH, &nBuf);
							if (hRes == S_OK) wsprintf(szBuf, TEXT("%d"), nBuf);
							else szBuf[0]='\0';
						}; break;
						case SHELLLINKTYPE_GETPATH:
						{
							WIN32_FIND_DATA fd;

							hRes=psl->GetPath(szBuf, MAX_PATH, &fd, SLGP_UNCPRIORITY);
							if (hRes != S_OK) szBuf[0]='\0';
						}; break;
						case SHELLLINKTYPE_GETSHOWMODE:
						{
							hRes=psl->GetShowCmd(&nBuf);
							if (hRes == S_OK) wsprintf(szBuf, TEXT("%d"), nBuf);
							else szBuf[0]='\0';
						}; break;
						case SHELLLINKTYPE_GETWORKINGDIR:
						{
							hRes=psl->GetWorkingDirectory(szBuf, MAX_PATH);
							if (hRes != S_OK) szBuf[0]='\0';
						}; break;
					}
				}
				else
				{
					//Set
					switch(nType)
					{
						case SHELLLINKTYPE_SETARGS:
						{
							hRes=psl->SetArguments(szBuf2);
						}; break;
						case SHELLLINKTYPE_SETDESC:
						{
							hRes=psl->SetDescription(szBuf2);
						}; break;
						case SHELLLINKTYPE_SETHOTKEY:
						{
							wHotkey=(unsigned short)myatoi(szBuf2);
							hRes=psl->SetHotkey(wHotkey);
						}; break;
						case SHELLLINKTYPE_SETICONLOC:
						{
							hRes=psl->GetIconLocation(szBuf, MAX_PATH, &nBuf);
							if (hRes == S_OK)
								hRes=psl->SetIconLocation(szBuf2, nBuf);
						}; break;
						case SHELLLINKTYPE_SETICONINDEX:
						{
							int nBuf2;
							nBuf=myatoi(szBuf2);

							hRes=psl->GetIconLocation(szBuf, MAX_PATH, &nBuf2);
							if (hRes == S_OK)
								hRes=psl->SetIconLocation(szBuf, nBuf);
						}; break;
						case SHELLLINKTYPE_SETPATH:
						{
							hRes=psl->SetPath(szBuf2);
						}; break;
						case SHELLLINKTYPE_SETSHOWMODE:
						{
							nBuf=myatoi(szBuf2);
							hRes=psl->SetShowCmd(nBuf);
						}; break;
						case SHELLLINKTYPE_SETWORKINGDIR:
						{
							hRes=psl->SetWorkingDirectory(szBuf2);
						}; break;
						case SHELLLINKTYPE_SETRUNASADMIN:
						{
							IShellLinkDataList* pdl;
							hRes=psl->QueryInterface(IID_IShellLinkDataList, (void**)&pdl);
							if (hRes == S_OK)
							{
								DWORD dwFlags = 0;
								hRes=pdl->GetFlags(&dwFlags);
								if (hRes == S_OK && (dwFlags & SLDF_RUNAS_USER) != SLDF_RUNAS_USER)
									hRes=pdl->SetFlags(dwFlags | SLDF_RUNAS_USER);

								pdl->Release();
							}
						}; break;
						case SHELLLINKTYPE_SETAPPMODELID:
						{
							if (local_wcslen(szBuf2) < 1)
							{
								pushstring(TEXT("-1"));
								return;
							}

							PROPVARIANT pv;
							hRes = LocalInitPropVariantFromString(szBuf2, &pv);

							if (hRes == S_OK)
							{
								hRes = psl->QueryInterface(IID_IPropertyStore, (void**)&pps);
								if (hRes == S_OK)
								{
									hRes = pps->SetValue(PKEY_AppUserModel_ID, pv);
									if (hRes == S_OK)
									{
										hRes = pps->Commit();
									}

									PropVariantClear(&pv);
								}
							}
						}; break;
					}
					if (hRes == S_OK) hRes=ppf->Save(NULL, FALSE);
					#ifdef SHELLLINK_DEBUG
					else MessageBox(hwndParent, TEXT("ERROR: Save()"), TEXT("ShellLink plug-in"), MB_OK);
					#endif
				}
			}
			#ifdef SHELLLINK_DEBUG
			else MessageBox(hwndParent, TEXT("ERROR: Load()"), TEXT("ShellLink plug-in"), MB_OK);
			#endif
		}
		#ifdef SHELLLINK_DEBUG
		else MessageBox(hwndParent, TEXT("CShellLink::Initialise, Failed in call to QueryInterface for IPersistFile, HRESULT was %x\n"), TEXT("ShellLink plug-in"), MB_OK);
		#endif

		// Cleanup:
		if (pps) pps->Release();
		if (ppf) ppf->Release();
		if (psl) psl->Release();
	}
	#ifdef SHELLLINK_DEBUG
	else MessageBox(hwndParent, TEXT("ERROR: CoCreateInstance()"), TEXT("ShellLink plug-in"), MB_OK);
	#endif

	if (hRes == S_OK)
	{
		if (nType <= SHELLLINKTYPE_GETWORKINGDIR) pushstring(szBuf);
		else pushstring(TEXT("0"));
	}
	else
	{
		if (nType <= SHELLLINKTYPE_GETWORKINGDIR) pushstring(TEXT(""));
		else pushstring(TEXT("-1"));
	}

  LocalFree(szBuf);
  LocalFree(szBuf2);
}

BOOL WINAPI DllMain(HANDLE hInst, ULONG ul_reason_for_call, LPVOID lpReserved)
{
	return TRUE;
}
