@echo off
set command=%1
set build=%2
set arch=%3
set compiler=%4
set buildFlag=
set archFlag=
set compilerFlag=

if "%command%" == "" (
    set command=build
)
if not "%build%" == "" (
    set buildFlag="--build=%build%"
)
if not "%arch%" == "" (
    set archFlag="--arch=%arch%"
)
if not "%compiler%" == "" (
    set compilerFlag="--compiler=%compiler%"
)

dub %command% %buildFlag% %archFlag% %compilerFlag%
dub %command% denjin:maths %buildFlag% %archFlag% %compilerFlag%
dub %command% denjin:misc %buildFlag% %archFlag% %compilerFlag%
dub %command% denjin:renderer %buildFlag% %archFlag% %compilerFlag%
dub %command% denjin:window %buildFlag% %archFlag% %compilerFlag%