@echo off
setlocal EnableDelayedExpansion

set SIGNTOOL=%1
set arch_dir=%2

set bin_path=.out/%arch_dir%/bin/

%SIGNTOOL% sign /a /a /n "KiCad Services Corporation" /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /v %bin_path%*.exe
%SIGNTOOL% sign /a /a /n "KiCad Services Corporation" /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /v %bin_path%*.dll
%SIGNTOOL% sign /a /a /n "KiCad Services Corporation" /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /v %bin_path%*.kiface