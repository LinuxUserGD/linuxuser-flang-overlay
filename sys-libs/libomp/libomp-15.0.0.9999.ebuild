# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Virtual for Clang Compiler"
SLOT="${PV}"
KEYWORDS=""
IUSE="
	cuda debug hwloc offload ompt test
	llvm_targets_AMDGPU llvm_targets_NVPTX
	+virtual
"
