# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Virtual for Clang Compiler"
SLOT="${PV}"
KEYWORDS="~amd64 ~arm ~arm64 ~ppc64"
IUSE="debug default-compiler-rt default-libcxx default-lld doc llvm-libunwind +static-analyzer test xml kernel_FreeBSD"
RDEPEND="sys-devel/llvm"
