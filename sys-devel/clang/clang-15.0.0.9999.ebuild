# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Virtual for Clang Compiler"
SLOT="$(ver_cut 1)"
KEYWORDS=""
IUSE="debug default-compiler-rt default-libcxx default-lld doc llvm-libunwind +static-analyzer test xml kernel_FreeBSD +virtual"
