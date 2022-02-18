# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python3_{8..10} )
inherit cmake llvm.org multilib-minimal pax-utils python-any-r1 \
	toolchain-funcs

DESCRIPTION="Low Level Virtual Machine"
HOMEPAGE="https://llvm.org/"

# Those are in lib/Targets, without explicit CMakeLists.txt mention
ALL_LLVM_EXPERIMENTAL_TARGETS=( ARC CSKY M68k )
# Keep in sync with CMakeLists.txt
ALL_LLVM_TARGETS=( AArch64 AMDGPU ARM AVR BPF Hexagon Lanai Mips MSP430
	NVPTX PowerPC RISCV Sparc SystemZ VE WebAssembly X86 XCore
	"${ALL_LLVM_EXPERIMENTAL_TARGETS[@]}" )
ALL_LLVM_TARGETS=( "${ALL_LLVM_TARGETS[@]/#/llvm_targets_}" )

# Additional licenses:
# 1. OpenBSD regex: Henry Spencer's license ('rc' in Gentoo) + BSD.
# 2. xxhash: BSD.
# 3. MD5 code: public-domain.
# 4. ConvertUTF.h: TODO.

LICENSE="Apache-2.0-with-LLVM-exceptions UoI-NCSA BSD public-domain rc"
SLOT="$(ver_cut 1)"
KEYWORDS=""
IUSE="+binutils-plugin debug doc exegesis libedit +libffi mlir ncurses test xar xml z3
	kernel_Darwin ${ALL_LLVM_TARGETS[*]}"
REQUIRED_USE="|| ( ${ALL_LLVM_TARGETS[*]} )"
RESTRICT="!test? ( test )"

RDEPEND="
	sys-libs/zlib:0=[${MULTILIB_USEDEP}]
	exegesis? ( dev-libs/libpfm:= )
	binutils-plugin? ( >=sys-devel/binutils-2.31.1-r4:*[plugins] )
	libedit? ( dev-libs/libedit:0=[${MULTILIB_USEDEP}] )
	libffi? ( >=dev-libs/libffi-3.0.13-r1:0=[${MULTILIB_USEDEP}] )
	ncurses? ( >=sys-libs/ncurses-5.9-r3:0=[${MULTILIB_USEDEP}] )
	xar? ( app-arch/xar )
	xml? ( dev-libs/libxml2:2=[${MULTILIB_USEDEP}] )
	z3? ( >=sci-mathematics/z3-4.7.1:0=[${MULTILIB_USEDEP}] )"
DEPEND="${RDEPEND}
	binutils-plugin? ( sys-libs/binutils-libs )"
BDEPEND="
	dev-lang/perl
	>=dev-util/cmake-3.16
	sys-devel/gnuconfig
	kernel_Darwin? (
		<sys-libs/libcxx-$(ver_cut 1-3).9999
		>=sys-devel/binutils-apple-5.1
	)
	doc? ( $(python_gen_any_dep '
		dev-python/recommonmark[${PYTHON_USEDEP}]
		dev-python/sphinx[${PYTHON_USEDEP}]
	') )
	libffi? ( virtual/pkgconfig )
	${PYTHON_DEPS}"
# There are no file collisions between these versions but having :0
# installed means llvm-config there will take precedence.
RDEPEND="${RDEPEND}
	!sys-devel/llvm:0"
PDEPEND="sys-devel/llvm-common
	binutils-plugin? ( >=sys-devel/llvmgold-${SLOT} )"

LLVM_COMPONENTS=( llvm cmake third-party mlir flang clang )
LLVM_MANPAGES=build
LLVM_PATCHSET=9999-r3
llvm.org_set_globals

python_check_deps() {
	use doc || return 0

	has_version -b "dev-python/recommonmark[${PYTHON_USEDEP}]" &&
	has_version -b "dev-python/sphinx[${PYTHON_USEDEP}]"
}

check_live_ebuild() {
	local prod_targets=(
		$(sed -n -e '/set(LLVM_ALL_TARGETS/,/)/p' CMakeLists.txt \
			| tail -n +2 | head -n -1)
	)
	local all_targets=(
		lib/Target/*/
	)
	all_targets=( "${all_targets[@]#lib/Target/}" )
	all_targets=( "${all_targets[@]%/}" )

	local exp_targets=() i
	for i in "${all_targets[@]}"; do
		has "${i}" "${prod_targets[@]}" || exp_targets+=( "${i}" )
	done
	# reorder
	all_targets=( "${prod_targets[@]}" "${exp_targets[@]}" )

	if [[ ${exp_targets[*]} != ${ALL_LLVM_EXPERIMENTAL_TARGETS[*]} ]]; then
		eqawarn "ALL_LLVM_EXPERIMENTAL_TARGETS is outdated!"
		eqawarn "    Have: ${ALL_LLVM_EXPERIMENTAL_TARGETS[*]}"
		eqawarn "Expected: ${exp_targets[*]}"
		eqawarn
	fi

	if [[ ${all_targets[*]} != ${ALL_LLVM_TARGETS[*]#llvm_targets_} ]]; then
		eqawarn "ALL_LLVM_TARGETS is outdated!"
		eqawarn "    Have: ${ALL_LLVM_TARGETS[*]#llvm_targets_}"
		eqawarn "Expected: ${all_targets[*]}"
	fi
}

check_distribution_components() {
	if [[ ${CMAKE_MAKEFILE_GENERATOR} == ninja ]]; then
		local all_targets=() my_targets=() l
		cd "${BUILD_DIR}" || die

		while read -r l; do
			if [[ ${l} == install-*-stripped:* ]]; then
				l=${l#install-}
				l=${l%%-stripped*}

				case ${l} in
					# shared libs
					LLVM|LLVMgold)
						;;
					# TableGen lib + deps
					LLVMDemangle|LLVMSupport|LLVMTableGen)
						;;
					# static libs
					LLVM*)
						continue
						;;
					# meta-targets
					distribution|llvm-libraries)
						continue
						;;
					# used only w/ USE=doc
					docs-llvm-html)
						use doc || continue
						;;
				esac

				all_targets+=( "${l}" )
			fi
		done < <(ninja -t targets all)

		while read -r l; do
			my_targets+=( "${l}" )
		done < <(get_distribution_components $"\n")

		local add=() remove=()
		for l in "${all_targets[@]}"; do
			if ! has "${l}" "${my_targets[@]}"; then
				add+=( "${l}" )
			fi
		done
		for l in "${my_targets[@]}"; do
			if ! has "${l}" "${all_targets[@]}"; then
				remove+=( "${l}" )
			fi
		done

		if [[ ${#add[@]} -gt 0 || ${#remove[@]} -gt 0 ]]; then
			eqawarn "get_distribution_components() is outdated!"
			eqawarn "   Add: ${add[*]}"
			eqawarn "Remove: ${remove[*]}"
		fi
		cd - >/dev/null || die
	fi
}

src_prepare() {
	# disable use of SDK on OSX, bug #568758
	sed -i -e 's/xcrun/false/' utils/lit/lit/util.py || die

	# Update config.guess to support more systems
	cp "${BROOT}/usr/share/gnuconfig/config.guess" cmake/ || die

	# Verify that the live ebuild is up-to-date
	check_live_ebuild

	llvm.org_src_prepare
}

# Is LLVM being linked against libc++?
is_libcxx_linked() {
	local code='#include <ciso646>
#if defined(_LIBCPP_VERSION)
	HAVE_LIBCXX
#endif
'
	local out=$($(tc-getCXX) ${CXXFLAGS} ${CPPFLAGS} -x c++ -E -P - <<<"${code}") || return 1

	[[ ${out} == *HAVE_LIBCXX* ]]
}

get_distribution_components() {
	local sep=${1-;}

	local out=(
		# shared libs
		LLVM
		LTO
		Remarks

		# tools
		llvm-config

		# common stuff
		cmake-exports
		llvm-headers

		# libraries needed for clang-tblgen
		LLVMDemangle
		LLVMSupport
		LLVMTableGen

		# fortran needed for flang
		FortranCommon
		FortranDecimal
		FortranEvaluate
		FortranLower
		FortranParser
		FortranRuntime
		FortranSemantics

		#mlir needed for flang
		MLIRControlFlowToLLVM
		MLIRSCFToControlFlow
		MLIRVectorUtils
		MLIRControlFlowToSPIRV
		MLIRVectorTransforms
		MLIRAffineAnalysis
		MLIRBufferization
		MLIRBufferizationTransforms
		MLIRAffineBufferizableOpInterfaceImpl
		MLIRModuleBufferization
		MLIRSCFUtils
		MLIRTensorTilingInterfaceImpl
		MLIRTensorUtils
		MLIRArithmeticUtils
		MLIRControlFlow
		MLIRQuantUtils
		MLIRQuantTransforms
		MLIRSparseTensorPipelines
		MLIRTensorInferTypeOpInterfaceImpl
		MLIRBufferizationToMemRef
		MLIRMemRefTestPasses
		MLIRTensorTestPasses

		MLIRArithmetic
		MLIRArithmeticToLLVM
		MLIRArithmeticToLLVM
		MLIRArithmeticToSPIRV
		MLIRArithmeticTransforms
		MLIRAMXToLLVMIRTranslation
		MLIRArmNeonToLLVMIRTranslation
		MLIRArmSVEToLLVMIRTranslation
		MLIRCAPIAsync
		MLIRCAPIConversion
		MLIRCAPIDebug
		MLIRCAPIGPU
		MLIRCAPISparseTensor
		MLIRLspServerLib
		MLIROpenACCToLLVMIRTranslation
		MLIROpenMPToLLVMIRTranslation
		MLIRTargetLLVMIRImport
		MLIRToLLVMIRTranslationRegistration
		MLIRX86VectorToLLVMIRTranslation
		MLIRTargetCpp
		MLIRLLVMCommonConversion
		MLIRGPUTransforms
		MLIRSparseTensorUtils
		MLIRMemRefToSPIRV
		MLIRArmNeon2dToIntr
		MLIRMathToLLVM
		MLIRMathToSPIRV
		MLIROpenACCToSCF
		MLIRVectorToGPU
		MLIREmitC
		MLIRMemRefToLLVM
		MLIRGPUOps
		MLIRTilingInterface
		MLIRLinalgBufferizableOpInterfaceImpl
		bash-autocomplete
		c-index-test

		#clang needed for flang
		clang-check
		clang-cmake-exports
		clang-cpp
		clang-extdef-mapping
		clang-format
		clang-headers
		clang-libraries
		clang-offload-bundler
		clang-offload-wrapper
		clang-refactor
		clang-rename
		clang-resource-headers
		clang-scan-deps
		clang
		clangAPINotes
		clangARCMigrate
		clangAST
		clangASTMatchers
		clangAnalysis
		clangCodeGen
		clangCrossTU
		clangDependencyScanning
		clangDirectoryWatcher
		clangDynamicASTMatchers
		clangEdit
		clangFormat
		clangFrontend
		clangFrontendTool
		clangHandleCXX
		clangHandleLLVM
		clangIndex
		clangIndexSerialization
		clangInterpreter
		clangLex
		clangParse
		clangRewrite
		clangRewriteFrontend
		clangSema
		clangSerialization
		clangStaticAnalyzerCheckers
		clangStaticAnalyzerCore
		clangStaticAnalyzerFrontend
		clangTesting
		clangTooling
		clangToolingASTDiff
		clangToolingCore
		clangToolingInclusions
		clangToolingRefactoring
		clangToolingSyntax
		clangTransformer
		diagtool
		docs-clang-html
		docs-clang-man
		docs-flang-html
		docs-flang-man

		#f18 needed for flang
		f18-parse-demo

		#f18
		fir-opt
		flang-new
		flangFrontend
		flangFrontendTool
		hmaptool

		libclang-headers
		libclang-python-bindings
		libclang

		llvm-otool
		llvm-windres

		mlir-linalg-ods-yaml-gen
		mlir-lsp-server

		scan-build
		scan-view
		tco
		#FIROptimizer

		# other llvm distribution components
		MLIRCAPILLVM
		MLIRReduceLib
		clang-repl
		scan-build-py
		MLIRReconcileUnrealizedCasts
	)

	if multilib_is_native_abi; then
		out+=(
			# utilities
			llvm-tblgen
			FileCheck
			llvm-PerfectShuffle
			count
			not
			yaml-bench

			# tools
			bugpoint
			dsymutil
			llc
			lli
			lli-child-target
			llvm-addr2line
			llvm-ar
			llvm-as
			llvm-bcanalyzer
			llvm-bitcode-strip
			llvm-c-test
			llvm-cat
			llvm-cfi-verify
			llvm-config
			llvm-cov
			llvm-cvtres
			llvm-cxxdump
			llvm-cxxfilt
			llvm-cxxmap
			llvm-diff
			llvm-dis
			llvm-dlltool
			llvm-dwarfdump
			llvm-dwp
			#llvm-elfabi
			llvm-exegesis
			llvm-extract
			llvm-gsymutil
			llvm-ifs
			llvm-install-name-tool
			llvm-jitlink
			llvm-jitlink-executor
			llvm-lib
			llvm-libtool-darwin
			llvm-link
			llvm-lipo
			llvm-lto
			llvm-lto2
			llvm-mc
			llvm-mca
			llvm-ml
			llvm-modextract
			llvm-mt
			llvm-nm
			llvm-objcopy
			llvm-objdump
			llvm-opt-report
			llvm-otool
			llvm-pdbutil
			llvm-profdata
			llvm-profgen
			llvm-ranlib
			llvm-rc
			llvm-readelf
			llvm-readobj
			llvm-reduce
			llvm-rtdyld
			llvm-sim
			llvm-size
			llvm-split
			llvm-stress
			llvm-strings
			llvm-strip
			llvm-symbolizer
			llvm-tapi-diff
			llvm-undname
			llvm-windres
			llvm-xray
			obj2yaml
			opt
			sancov
			sanstats
			split-file
			verify-uselistorder
			yaml2obj

			# python modules
			opt-viewer
		)

		if llvm_are_manpages_built; then
			out+=(
				# manpages
				docs-dsymutil-man
				docs-llvm-dwarfdump-man
				docs-llvm-man
			)
		fi
		use doc && out+=(
			docs-llvm-html
		)

		use binutils-plugin && out+=(
			LLVMgold
		)
	fi

	if use mlir; then
		out+=( flang-cmake-exports flang-libraries clangBasic clangDriver MLIRROCDLToLLVMIRTranslation MLIRNVVMToLLVMIRTranslation MLIRAffineToStandard MLIRMemRef  MLIRGPUToNVVMTransforms MLIRMemRef  MLIRLinalgToStandard MLIRMemRef  MLIRSCFToGPU MLIRMemRef  MLIRShapeToStandard MLIRMemRef  MLIRStandardToLLVM MLIRDataLayoutInterfaces  MLIRStandardToLLVM MLIRMath  MLIRStandardToLLVM MLIRMemRef  MLIRStandardToSPIRV MLIRMath  MLIRStandardToSPIRV MLIRMemRef  MLIRTosaToLinalg MLIRMath  MLIRTosaToLinalg MLIRMemRef  MLIRVectorToLLVM MLIRArmSVETransforms  MLIRVectorToLLVM MLIRAMX  MLIRVectorToLLVM MLIRAMXTransforms  MLIRVectorToLLVM MLIRMemRef  MLIRVectorToLLVM MLIRTargetLLVMIRExport  MLIRVectorToLLVM MLIRX86Vector  MLIRVectorToLLVM MLIRX86VectorTransforms  MLIRVectorToSCF MLIRMemRef  MLIRAffine MLIRMemRef  MLIRAffineTransforms MLIRMemRef MLIRDataLayoutInterfaces MLIRDLTI MLIRMemRef MLIRLLVMToLLVMIRTranslation  MLIRLinalgAnalysis MLIRMemRef  MLIRLinalg MLIRDialectUtils  MLIRLinalg MLIRMemRef  MLIRLinalgTransforms MLIRMemRef  MLIRSCF MLIRMemRef  MLIRSCFTransforms MLIRMemRef  MLIRShapeOpsTransforms MLIRMemRef  MLIRStandardOpsTransforms MLIRMemRef  MLIRTensorTransforms MLIRMemRef  MLIRVector MLIRDialectUtils  MLIRVector MLIRMemRef  MLIRVector MLIRDataLayoutInterfaces  MLIRExecutionEngine MLIRLLVMToLLVMIRTranslation  MLIRExecutionEngine MLIRTargetLLVMIRExport  MLIRJitRunner MLIRArmSVETransforms  MLIRJitRunner MLIRAMX  MLIRJitRunner MLIRAMXTransforms  MLIRJitRunner MLIRDLTI  MLIRJitRunner MLIRMath  MLIRJitRunner MLIRMathTransforms  MLIRJitRunner MLIRMemRef  MLIRJitRunner MLIRMemRefTransforms  MLIRJitRunner MLIRMemRefUtils  MLIRJitRunner MLIRSparseTensor  MLIRJitRunner MLIRSparseTensorTransforms  MLIRJitRunner MLIRX86Vector  MLIRJitRunner MLIRX86VectorTransforms  MLIRJitRunner MLIRLLVMToLLVMIRTranslation  MLIRJitRunner MLIRTargetLLVMIRExport  MLIRTransformUtils MLIRMemRef  MLIRTransforms MLIRMemRef  MLIRCAPIRegistration MLIRLLVMToLLVMIRTranslation  MLIRCAPIRegistration MLIRArmSVETransforms  MLIRCAPIRegistration MLIRAMX  MLIRCAPIRegistration MLIRAMXTransforms  MLIRCAPIRegistration MLIRDLTI  MLIRCAPIRegistration MLIRMath  MLIRCAPIRegistration MLIRMathTransforms  MLIRCAPIRegistration MLIRMemRef  MLIRCAPIRegistration MLIRMemRefTransforms  MLIRCAPIRegistration MLIRMemRefUtils  MLIRCAPIRegistration MLIRSparseTensor  MLIRCAPIRegistration MLIRSparseTensorTransforms  MLIRCAPIRegistration MLIRX86Vector  MLIRCAPIRegistration MLIRX86VectorTransforms  MLIRTestDialect MLIRDataLayoutInterfaces  MLIRTestDialect MLIRDLTI  MLIRMlirOptMain MLIRArmSVETransforms  MLIRMlirOptMain MLIRAMX  MLIRMlirOptMain MLIRAMXTransforms  MLIRMlirOptMain MLIRDLTI  MLIRMlirOptMain MLIRMath  MLIRMlirOptMain MLIRMathTransforms  MLIRMlirOptMain MLIRMemRef  MLIRMlirOptMain MLIRMemRefTransforms  MLIRMlirOptMain MLIRMemRefUtils  MLIRMlirOptMain MLIRSparseTensor  MLIRMlirOptMain MLIRSparseTensorTransforms  MLIRMlirOptMain MLIRX86Vector  MLIRMlirOptMain MLIRX86VectorTransforms  MLIRMlirOptMain MLIRComplexToStandard  MLIRMlirOptMain MLIRMathToLibm  MLIRMlirOptMain MLIROpenACCToLLVM  MLIRMlirOptMain MLIRTosaToSCF  MLIRMlirOptMain MLIRTosaToStandard  MLIRMlirOptMain MLIRTestStandardToLLVM  MLIRMlirOptMain MLIRDLTITestPasses  MLIRMlirOptMain MLIRGPUTestPasses  MLIRMlirOptMain MLIRLinalgTestPasses  MLIRMlirOptMain MLIRMathTestPasses  MLIRMlirOptMain MLIRSCFTestPasses  MLIRMlirOptMain MLIRStandardOpsTestPasses  MLIRMlirOptMain MLIRVectorTestPasses  MLIRMlirOptMain MLIRTestAnalysis MLIR  MLIRAffine  MLIRAffineToStandard MLIRAffineTransforms MLIRAffineTransformsTestPasses MLIRAffineUtils MLIRAnalysis MLIRArmNeon  MLIRArmSVE MLIRAsync MLIRAsyncToLLVM MLIRAsyncTransforms MLIRCAPIIR MLIRCAPILinalg MLIRCAPIRegistration MLIRCAPISCF MLIRCAPIShape MLIRCAPIStandard MLIRCAPITensor MLIRCAPITransforms MLIRCallInterfaces MLIRCastInterfaces MLIRComplex MLIRComplexToLLVM MLIRControlFlowInterfaces MLIRCopyOpInterface MLIRDerivedAttributeOpInterface MLIRDialect MLIRExecutionEngine MLIRGPUToGPURuntimeTransforms MLIRGPUToNVVMTransforms MLIRGPUToROCDLTransforms MLIRGPUToSPIRV MLIRGPUToVulkanTransforms MLIRIR MLIRInferTypeOpInterface MLIRJitRunner MLIRLLVMIR MLIRLLVMIRTransforms MLIRLinalg MLIRLinalgAnalysis MLIRLinalgToLLVM MLIRLinalgToSPIRV MLIRLinalgToStandard MLIRLinalgTransforms MLIRLinalgUtils MLIRLoopLikeInterface MLIRMlirOptMain MLIRNVVMIR MLIROpenACC MLIROpenMP MLIROpenMPToLLVM MLIROptLib MLIRPDL MLIRPDLInterp MLIRPDLToPDLInterp MLIRParser MLIRPass MLIRPresburger  MLIRQuant MLIRROCDLIR MLIRReduce MLIRRewrite MLIRSCF MLIRSCFToGPU MLIRSCFToOpenMP MLIRSCFToSPIRV MLIRSCFTransforms MLIRSPIRV MLIRSPIRVBinaryUtils MLIRSPIRVConversion MLIRSPIRVDeserialization MLIRSPIRVModuleCombiner MLIRSPIRVSerialization MLIRSPIRVTestPasses MLIRSPIRVToLLVM MLIRSPIRVTransforms MLIRSPIRVTranslateRegistration MLIRSPIRVUtils MLIRShape MLIRShapeOpsTransforms MLIRShapeTestPasses MLIRShapeToStandard MLIRSideEffectInterfaces MLIRStandard MLIRStandardOpsTransforms MLIRStandardToLLVM MLIRStandardToSPIRV MLIRSupport MLIRSupportIndentedOstream MLIRTableGen MLIRTensor MLIRTensorTransforms MLIRTestDialect MLIRTestIR MLIRTestPass MLIRTestReducer MLIRTestRewrite MLIRTestTransforms MLIRTosa MLIRTosaTestPasses MLIRTosaToLinalg MLIRTosaTransforms MLIRTransformUtils MLIRTransforms MLIRTranslation MLIRVector MLIRVectorInterfaces MLIRVectorToLLVM MLIRVectorToROCDL MLIRVectorToSCF MLIRVectorToSPIRV MLIRViewLikeInterface mlir-cmake-exports mlir-cpu-runner mlir-headers mlir-opt mlir-reduce mlir-tblgen mlir-translate mlir_async_runtime mlir_c_runner_utils mlir_runner_utils )
	fi

	printf "%s${sep}" "${out[@]}"
}

multilib_src_configure() {
	local ffi_cflags ffi_ldflags
	if use libffi; then
		ffi_cflags=$($(tc-getPKG_CONFIG) --cflags-only-I libffi)
		ffi_ldflags=$($(tc-getPKG_CONFIG) --libs-only-L libffi)
	fi

	local libdir=$(get_libdir)
	local mycmakeargs=(
		# disable appending VCS revision to the version to improve
		# direct cache hit ratio
		-DLLVM_APPEND_VC_REV=OFF
		-DCMAKE_INSTALL_PREFIX="${EPREFIX}/usr/lib/llvm/${SLOT}"
		-DLLVM_LIBDIR_SUFFIX=${libdir#lib}

		-DBUILD_SHARED_LIBS=OFF
		-DLLVM_BUILD_LLVM_DYLIB=ON
		-DLLVM_LINK_LLVM_DYLIB=ON
		-DLLVM_DISTRIBUTION_COMPONENTS=$(get_distribution_components)
		# cheap hack: LLVM combines both anyway, and the only difference
		# is that the former list is explicitly verified at cmake time
		-DLLVM_TARGETS_TO_BUILD=""
		-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="${LLVM_TARGETS// /;}"
		-DLLVM_BUILD_TESTS=$(usex test)
		-DLLVM_ENABLE_FFI=$(usex libffi)
		-DLLVM_ENABLE_LIBEDIT=$(usex libedit)
		-DLLVM_ENABLE_TERMINFO=$(usex ncurses)
		-DLLVM_ENABLE_LIBXML2=$(usex xml)
		-DLLVM_ENABLE_ASSERTIONS=$(usex debug)
		-DLLVM_ENABLE_LIBPFM=$(usex exegesis)
		-DLLVM_ENABLE_EH=ON
		-DLLVM_ENABLE_RTTI=ON
		-DLLVM_ENABLE_Z3_SOLVER=$(usex z3)
		-DLLVM_HOST_TRIPLE="${CHOST}"

		-DFFI_INCLUDE_DIR="${ffi_cflags#-I}"
		-DFFI_LIBRARY_DIR="${ffi_ldflags#-L}"
		# used only for llvm-objdump tool
		-DLLVM_HAVE_LIBXAR=$(multilib_native_usex xar 1 0)

		-DPython3_EXECUTABLE="${PYTHON}"

		# disable OCaml bindings (now in dev-ml/llvm-ocaml)
		-DOCAMLFIND=NO
	)

	use mlir && mycmakeargs+=(
		-DLLVM_ENABLE_PROJECTS="mlir;flang;clang"
	)

	if is_libcxx_linked; then
		# Smart hack: alter version suffix -> SOVERSION when linking
		# against libc++. This way we won't end up mixing LLVM libc++
		# libraries with libstdc++ clang, and the other way around.
		mycmakeargs+=(
			-DLLVM_VERSION_SUFFIX="libcxx"
			-DLLVM_ENABLE_LIBCXX=ON
		)
	fi

#	Note: go bindings have no CMake rules at the moment
#	but let's kill the check in case they are introduced
#	if ! multilib_is_native_abi || ! use go; then
		mycmakeargs+=(
			-DGO_EXECUTABLE=GO_EXECUTABLE-NOTFOUND
		)
#	fi

	use test && mycmakeargs+=(
		-DLLVM_LIT_ARGS="$(get_lit_flags)"
	)

	if multilib_is_native_abi; then
		local build_docs=OFF
		if llvm_are_manpages_built; then
			build_docs=ON
			mycmakeargs+=(
				-DCMAKE_INSTALL_MANDIR="${EPREFIX}/usr/lib/llvm/${SLOT}/share/man"
				-DLLVM_INSTALL_SPHINX_HTML_DIR="${EPREFIX}/usr/share/doc/${PF}/html"
				-DSPHINX_WARNINGS_AS_ERRORS=OFF
			)
		fi

		mycmakeargs+=(
			-DLLVM_BUILD_DOCS=${build_docs}
			-DLLVM_ENABLE_OCAMLDOC=OFF
			-DLLVM_ENABLE_SPHINX=${build_docs}
			-DLLVM_ENABLE_DOXYGEN=OFF
			-DLLVM_INSTALL_UTILS=ON
		)
		use binutils-plugin && mycmakeargs+=(
			-DLLVM_BINUTILS_INCDIR="${EPREFIX}"/usr/include
		)
	fi

	if tc-is-cross-compiler; then
		local tblgen="${EPREFIX}/usr/lib/llvm/${SLOT}/bin/llvm-tblgen"
		[[ -x "${tblgen}" ]] \
			|| die "${tblgen} not found or usable"
		mycmakeargs+=(
			-DCMAKE_CROSSCOMPILING=ON
			-DLLVM_TABLEGEN="${tblgen}"
		)
	fi

	# workaround BMI bug in gcc-7 (fixed in 7.4)
	# https://bugs.gentoo.org/649880
	# apply only to x86, https://bugs.gentoo.org/650506
	if tc-is-gcc && [[ ${MULTILIB_ABI_FLAG} == abi_x86* ]] &&
			[[ $(gcc-major-version) -eq 7 && $(gcc-minor-version) -lt 4 ]]
	then
		local CFLAGS="${CFLAGS} -mno-bmi"
		local CXXFLAGS="${CXXFLAGS} -mno-bmi"
	fi

	# LLVM can have very high memory consumption while linking,
	# exhausting the limit on 32-bit linker executable
	use x86 && local -x LDFLAGS="${LDFLAGS} -Wl,--no-keep-memory"

	# LLVM_ENABLE_ASSERTIONS=NO does not guarantee this for us, #614844
	use debug || local -x CPPFLAGS="${CPPFLAGS} -DNDEBUG"
	cmake_src_configure

	multilib_is_native_abi && check_distribution_components
}

multilib_src_compile() {
	cmake_build distribution

	pax-mark m "${BUILD_DIR}"/bin/llvm-rtdyld
	pax-mark m "${BUILD_DIR}"/bin/lli
	pax-mark m "${BUILD_DIR}"/bin/lli-child-target

	if use test; then
		pax-mark m "${BUILD_DIR}"/unittests/ExecutionEngine/Orc/OrcJITTests
		pax-mark m "${BUILD_DIR}"/unittests/ExecutionEngine/MCJIT/MCJITTests
		pax-mark m "${BUILD_DIR}"/unittests/Support/SupportTests
	fi
}

multilib_src_test() {
	# respect TMPDIR!
	local -x LIT_PRESERVES_TMP=1
	cmake_build check
}

src_install() {
	local MULTILIB_CHOST_TOOLS=(
		/usr/lib/llvm/${SLOT}/bin/llvm-config
	)

	local MULTILIB_WRAPPED_HEADERS=(
		/usr/include/llvm/Config/llvm-config.h
	)

	local LLVM_LDPATHS=()
	multilib-minimal_src_install

	# move wrapped headers back
	mv "${ED}"/usr/include "${ED}"/usr/lib/llvm/${SLOT}/include || die
}

multilib_src_install() {
	DESTDIR=${D} cmake_build install-distribution

	# move headers to /usr/include for wrapping
	rm -rf "${ED}"/usr/include || die
	mv "${ED}"/usr/lib/llvm/${SLOT}/include "${ED}"/usr/include || die

	LLVM_LDPATHS+=( "${EPREFIX}/usr/lib/llvm/${SLOT}/$(get_libdir)" )
}

multilib_src_install_all() {
	local revord=$(( 9999 - ${SLOT} ))
	newenvd - "60llvm-${revord}" <<-_EOF_
		PATH="${EPREFIX}/usr/lib/llvm/${SLOT}/bin"
		# we need to duplicate it in ROOTPATH for Portage to respect...
		ROOTPATH="${EPREFIX}/usr/lib/llvm/${SLOT}/bin"
		MANPATH="${EPREFIX}/usr/lib/llvm/${SLOT}/share/man"
		LDPATH="$( IFS=:; echo "${LLVM_LDPATHS[*]}" )"
	_EOF_

	docompress "/usr/lib/llvm/${SLOT}/share/man"
	llvm_install_manpages
}

pkg_postinst() {
	elog "You can find additional opt-viewer utility scripts in:"
	elog "  ${EROOT}/usr/lib/llvm/${SLOT}/share/opt-viewer"
	elog "To use these scripts, you will need Python along with the following"
	elog "packages:"
	elog "  dev-python/pygments (for opt-viewer)"
	elog "  dev-python/pyyaml (for all of them)"
}
