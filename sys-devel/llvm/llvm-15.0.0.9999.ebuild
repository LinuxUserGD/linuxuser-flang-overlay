# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python3_{8..10} )
inherit cmake llvm llvm.org multilib multilib-minimal prefix pax-utils python-single-r1 toolchain-funcs

DESCRIPTION="Low Level Virtual Machine"
HOMEPAGE="https://llvm.org/"

# Additional licenses:
# 1. OpenBSD regex: Henry Spencer's license ('rc' in Gentoo) + BSD.
# 2. xxhash: BSD.
# 3. MD5 code: public-domain.
# 4. ConvertUTF.h: TODO.

LICENSE="Apache-2.0-with-LLVM-exceptions UoI-NCSA BSD public-domain rc"
SLOT="$(ver_cut 1)"
KEYWORDS=""
IUSE="+binutils-plugin debug doc exegesis libedit +libffi mlir polly ncurses test xar xml z3"
RESTRICT="!test? ( test )"

RDEPEND="
	sys-libs/zlib:0=[${MULTILIB_USEDEP}]
	sys-libs/compiler-rt[virtual]
	sys-libs/compiler-rt-sanitizers[virtual]
	sys-devel/clang[virtual]
	sys-devel/clang-runtime[virtual]
	sys-devel/lld[virtual]
	sys-libs/libcxx[virtual]
	sys-libs/libcxxabi[virtual]
	sys-libs/llvm-libunwind[virtual]
	sys-devel/llvmgold[virtual]
	sys-libs/libomp[virtual]
	exegesis? ( dev-libs/libpfm:= )
	binutils-plugin? ( >=sys-devel/binutils-2.31.1-r4:*[plugins] )
	libedit? ( dev-libs/libedit:0=[${MULTILIB_USEDEP}] )
	libffi? ( >=dev-libs/libffi-3.0.13-r1:0=[${MULTILIB_USEDEP}] )
	ncurses? ( >=sys-libs/ncurses-5.9-r3:0=[${MULTILIB_USEDEP}] )
	xar? ( app-arch/xar )
	xml? ( dev-libs/libxml2:2=[${MULTILIB_USEDEP}] )
	z3? ( >=sci-mathematics/z3-4.7.1:0=[${MULTILIB_USEDEP}] )"
DEPEND="
	${RDEPEND}
	binutils-plugin? ( sys-libs/binutils-libs )
"
BDEPEND="
	${PYTHON_DEPS}
	dev-lang/perl
	>=dev-util/cmake-3.16
	sys-devel/gnuconfig
	kernel_Darwin? (
		<sys-libs/libcxx-$(ver_cut 1-3).9999
		>=sys-devel/binutils-apple-5.1
	)
	dev-python/recommonmark
	dev-python/sphinx
	libffi? ( virtual/pkgconfig )
"
# There are no file collisions between these versions but having :0
# installed means llvm-config there will take precedence.
RDEPEND="
	${RDEPEND}
	!sys-devel/llvm:0
"
PDEPEND="
	sys-devel/llvm-common
	binutils-plugin? ( >=sys-devel/llvmgold-${SLOT} )
"

LLVM_COMPONENTS=( llvm llvm/lib/Testing/Support llvm/utils/{lit,llvm-lit,unittest} llvm/utils/{UpdateTestChecks,update_cc_test_checks.py} clang/bindings clang/cmake clang/docs clang/examples clang/include clang/lib clang/unittests clang/utils clang/www llvm/benchmarks llvm/bindings llvm/cmake llvm/docs llvm/examples llvm/include llvm/lib llvm/projects llvm/resources llvm/runtimes llvm/test llvm/tools llvm/unittests llvm/utils mlir polly openmp utils cmake third-party cross-project-tests bolt libclc flang clang clang-tools-extra libcxx libcxxabi compiler-rt lld lldb llvm-libgcc libunwind runtimes pstl )
LLVM_MANPAGES=build
LLVM_PATCHSET=9999-r3
LLVM_USE_TARGETS=provide
llvm.org_set_globals


pkg_setup() {
	LLVM_MAX_SLOT=${SLOT} llvm_pkg_setup
	python-single-r1_pkg_setup
}

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

	if [[ ${exp_targets[*]} != ${ALL_LLVM_EXPERIMENTAL_TARGETS[*]} ]]; then
		eqawarn "ALL_LLVM_EXPERIMENTAL_TARGETS is outdated!"
		eqawarn "    Have: ${ALL_LLVM_EXPERIMENTAL_TARGETS[*]}"
		eqawarn "Expected: ${exp_targets[*]}"
		eqawarn
	fi

	if [[ ${prod_targets[*]} != ${ALL_LLVM_PRODUCTION_TARGETS[*]} ]]; then
		eqawarn "ALL_LLVM_PRODUCTION_TARGETS is outdated!"
		eqawarn "    Have: ${ALL_LLVM_PRODUCTION_TARGETS[*]}"
		eqawarn "Expected: ${prod_targets[*]}"
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
					LLVM|LLVMgold|MLIR|Polly)
						;;
					# TableGen lib + deps
					LLVMDemangle|LLVMSupport|LLVMTableGen|LLVMExtensions)
						;;
					# static libs
					LLVM*|MLIR*)
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
					# meta-targets
					clang-libraries|distribution)
						continue
						;;
					# tools
					clang|clangd|clang-*)
						;;
					# static libraries
					clang*|findAllSymbols)
						continue
						;;
					# conditional to USE=doc
					docs-clang-html|docs-clang-tools-html)
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

	# create extra parent dir for relative CLANG_RESOURCE_DIR access
	mkdir -p x/y || die
	BUILD_DIR=${WORKDIR}/x/y/clang

	llvm.org_src_prepare

	# add Gentoo Portage Prefix for Darwin (see prefix-dirs.patch)
	#eprefixify \
	#	lib/Lex/InitHeaderSearch.cpp \
	#	lib/Driver/ToolChains/Darwin.cpp || die
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

		# tools
		llvm-config
		LLVM
		LTO
		Remarks


		# common stuff
		clang-cmake-exports
		clang-headers
		clang-resource-headers
		ppc-htm-resource-headers
		libclang-headers

		# libs
		clang-cpp
		libclang


		# common stuff
		cmake-exports
		llvm-headers

		# other libraries

		aarch64-resource-headers
		arm-resource-headers
		clangExtractAPI
		clangSupport
		core-resource-headers
		cuda-resource-headers
		hexagon-resource-headers
		hip-resource-headers
		mips-resource-headers
		mlir-pdll-lsp-server
		obj.MLIRCAPIControlFlow
		opencl-resource-headers
		openmp-resource-headers
		ppc-resource-headers
		riscv-resource-headers
		systemz-resource-headers
		utility-resource-headers
		ve-resource-headers
		webassembly-resource-headers
		windows-resource-headers
		x86-resource-headers
		MLIRAffineAnalysis
		MLIRAffine
		MLIRAffineTransforms
		MLIRAffineUtils
		MLIRArithmetic
		MLIRArithmeticTransforms
		MLIRArithmeticUtils
		MLIRArmNeon
		MLIRArmSVE
		MLIRArmSVETransforms
		MLIRAsync
		MLIRAsyncTransforms
		MLIRAMX
		MLIRAMXTransforms
		MLIRBufferization
		MLIRBufferizationTransforms
		MLIRComplex
		MLIRControlFlow
		MLIRDLTI
		MLIREmitC
		MLIRFunc
		MLIRFuncTransforms
		MLIRGPUOps
		MLIRGPUTransforms
		MLIRAMDGPU
		MLIRLinalgAnalysis
		MLIRLinalg
		MLIRLinalgTransformOps
		MLIRLinalgTransforms
		MLIRLinalgUtils
		MLIRLLVMIRTransforms
		MLIRLLVMIR
		MLIRNVVMIR
		MLIRROCDLIR
		MLIRMath
		MLIRMathTransforms
		MLIRMemRef
		MLIRMemRefTransforms
		MLIRMemRefUtils
		MLIRMLProgram
		MLIRNVGPU
		MLIROpenACC
		MLIROpenMP
		MLIRPDL
		MLIRPDLInterp
		MLIRQuant
		MLIRExecutionEngineUtils
		MLIRQuantTransforms
		MLIRQuantUtils
		MLIRSCF
		MLIRSCFTransforms
		MLIRSCFUtils
		MLIRShape
		MLIRShapeOpsTransforms
		MLIRSparseTensor
		MLIRSparseTensorTransforms
		MLIRSparseTensorPipelines
		MLIRSparseTensorUtils
		MLIRSPIRV
		MLIRSPIRVModuleCombiner
		MLIRSPIRVConversion
		MLIRSPIRVTransforms
		MLIRSPIRVUtils
		MLIRTensor
		MLIRTensorInferTypeOpInterfaceImpl
		MLIRTensorTilingInterfaceImpl
		MLIRTensorTransforms
		MLIRTensorUtils
		MLIRTosa
		MLIRTosaTransforms
		MLIRTransformDialect
		MLIRVector
		MLIRVectorTransforms
		MLIRVectorUtils
		MLIRX86Vector
		MLIRX86VectorTransforms
		MLIRTosaTestPasses
		MLIRAffineToStandard
		MLIRFunc
		MLIRLLVMIR
		MLIRSCFToControlFlow
		MLIRTransforms
		MLIRLLVMToLLVMIRTranslation
		MLIRSCFToControlFlow
		MLIRAffineAnalysis
		MLIRAffine
		MLIRAffineTransforms
		MLIRAffineUtils
		MLIRArithmetic
		MLIRArithmeticTransforms
		MLIRArithmeticUtils
		MLIRArmNeon
		MLIRArmSVE
		MLIRArmSVETransforms
		MLIRAsync
		MLIRAsyncTransforms
		MLIRAMX
		MLIRAMXTransforms
		MLIRBufferization
		MLIRBufferizationTransforms
		MLIRComplex
		MLIRControlFlow
		MLIRDLTI
		MLIREmitC
		MLIRFunc
		MLIRFuncTransforms
		MLIRGPUOps
		MLIRGPUTransforms
		MLIRLinalgAnalysis
		MLIRLinalg
		MLIRLinalgTransformOps
		MLIRLinalgTransforms
		MLIRLinalgUtils
		MLIRLLVMIRTransforms
		MLIRLLVMIR
		MLIRNVVMIR
		MLIRROCDLIR
		MLIRMath
		MLIRMathTransforms
		MLIRMemRef
		MLIRMemRefTransforms
		MLIRMemRefUtils
		MLIRMLProgram
		MLIRNVGPU
		MLIROpenACC
		MLIROpenMP
		MLIRPDL
		MLIRPDLInterp
		MLIRQuant
		MLIRQuantTransforms
		MLIRQuantUtils
		MLIRSCF
		MLIRSCFTransforms
		MLIRSCFUtils
		MLIRShape
		MLIRShapeOpsTransforms
		MLIRSparseTensor
		MLIRSparseTensorTransforms
		MLIRSparseTensorPipelines
		MLIRSparseTensorUtils
		MLIRSPIRV
		MLIRSPIRVModuleCombiner
		MLIRSPIRVConversion
		MLIRSPIRVTransforms
		MLIRSPIRVUtils
		MLIRTensor
		MLIRTensorInferTypeOpInterfaceImpl
		MLIRTensorTilingInterfaceImpl
		MLIRTensorTransforms
		MLIRTensorUtils
		MLIRTosa
		MLIRTosaTransforms
		MLIRTransformDialect
		MLIRVector
		MLIRVectorTransforms
		MLIRVectorUtils
		MLIRX86Vector
		MLIRX86VectorTransforms
		MLIRTosaTestPasses
		MLIRPass
		MLIRAffineAnalysis
		MLIRAffine
		MLIRAffineTransforms
		MLIRAffineUtils
		MLIRArithmetic
		MLIRArithmeticTransforms
		MLIRArithmeticUtils
		MLIRArmNeon
		MLIRArmSVE
		MLIRArmSVETransforms
		MLIRAsync
		MLIRAsyncTransforms
		MLIRAMX
		MLIRAMXTransforms
		MLIRBufferization
		MLIRBufferizationTransforms
		MLIRComplex
		MLIRControlFlow
		MLIRDLTI
		MLIREmitC
		MLIRFunc
		MLIRFuncTransforms
		MLIRGPUOps
		MLIRGPUTransforms
		MLIRLinalgAnalysis
		MLIRLinalg
		MLIRLinalgTransformOps
		MLIRLinalgTransforms
		MLIRLinalgUtils
		MLIRLLVMIRTransforms
		MLIRLLVMIR
		MLIRNVVMIR
		MLIRROCDLIR
		MLIRMath
		MLIRMathTransforms
		MLIRMemRef
		MLIRMemRefTransforms
		MLIRMemRefUtils
		MLIRMLProgram
		MLIRNVGPU
		MLIROpenACC
		MLIROpenMP
		MLIRPDL
		MLIRPDLInterp
		MLIRQuant
		MLIRQuantTransforms
		MLIRQuantUtils
		MLIRSCF
		MLIRSCFTransforms
		MLIRSCFUtils
		MLIRShape
		MLIRShapeOpsTransforms
		MLIRSparseTensor
		MLIRSparseTensorTransforms
		MLIRSparseTensorPipelines
		MLIRSparseTensorUtils
		MLIRSPIRV
		MLIRSPIRVModuleCombiner
		MLIRSPIRVConversion
		MLIRSPIRVTransforms
		MLIRSPIRVUtils
		MLIRTensor
		MLIRTensorInferTypeOpInterfaceImpl
		MLIRTensorTilingInterfaceImpl
		MLIRTensorTransforms
		MLIRTensorUtils
		MLIRTosa
		MLIRTosaTransforms
		MLIRTransformDialect
		MLIRVector
		MLIRVectorTransforms
		MLIRVectorUtils
		MLIRX86Vector
		MLIRX86VectorTransforms
		MLIRTosaTestPasses
		MLIROpenMPToLLVM
		MLIRLLVMToLLVMIRTranslation
		MLIRTargetLLVMIRExport
		MLIRArithmetic
		MLIROpenMPToLLVM
		MLIRLLVMToLLVMIRTranslation
		MLIRTargetLLVMIRExport
		MLIRAffineAnalysis
		MLIRAffine
		MLIRAffineTransforms
		MLIRAffineUtils
		MLIRArithmetic
		MLIRArithmeticTransforms
		MLIRArithmeticUtils
		MLIRArmNeon
		MLIRArmSVE
		MLIRArmSVETransforms
		MLIRAsync
		MLIRAsyncTransforms
		MLIRAMX
		MLIRAMXTransforms
		MLIRBufferization
		MLIRBufferizationTransforms
		MLIRComplex
		MLIRControlFlow
		MLIRDLTI
		MLIREmitC
		MLIRFunc
		MLIRFuncTransforms
		MLIRGPUOps
		MLIRGPUTransforms
		MLIRLinalgAnalysis
		MLIRLinalg
		MLIRLinalgTransformOps
		MLIRLinalgTransforms
		MLIRLinalgUtils
		MLIRLLVMIRTransforms
		MLIRLLVMIR
		MLIRNVVMIR
		MLIRROCDLIR
		MLIRMath
		MLIRMathTransforms
		MLIRMemRef
		MLIRMemRefTransforms
		MLIRMemRefUtils
		MLIRMLProgram
		MLIRNVGPU
		MLIROpenACC
		MLIROpenMP
		MLIRPDL
		MLIRPDLInterp
		MLIRQuant
		MLIRQuantTransforms
		MLIRQuantUtils
		MLIRSCF
		MLIRSCFTransforms
		MLIRSCFUtils
		MLIRShape
		MLIRShapeOpsTransforms
		MLIRSparseTensor
		MLIRSparseTensorTransforms
		MLIRSparseTensorPipelines
		MLIRSparseTensorUtils
		MLIRSPIRV
		MLIRSPIRVModuleCombiner
		MLIRSPIRVConversion
		MLIRSPIRVTransforms
		MLIRSPIRVUtils
		MLIRTensor
		MLIRTensorInferTypeOpInterfaceImpl
		MLIRTensorTilingInterfaceImpl
		MLIRTensorTransforms
		MLIRTensorUtils
		MLIRTosa
		MLIRTosaTransforms
		MLIRTransformDialect
		MLIRVector
		MLIRVectorTransforms
		MLIRVectorUtils
		MLIRX86Vector
		MLIRX86VectorTransforms
		MLIRTosaTestPasses
		MLIROpenMPToLLVMIRTranslation
		MLIRLLVMToLLVMIRTranslation
		MLIRTargetLLVMIRExport
		MLIRAffineUtils
		MLIRFunc
		MLIRLLVMIR
		MLIROpenACC
		MLIROpenMP
		MLIRIR
		MLIRArithmeticToLLVM
		MLIRFuncToLLVM
		MLIRLLVMCommonConversion
		MLIRMemRefToLLVM
		MLIRAnalysis
		MLIRCallInterfaces
		MLIRControlFlowInterfaces
		MLIRInferTypeOpInterface
		MLIRPresburger
		MLIRLoopLikeInterface
		MLIRSideEffectInterfaces
		MLIRVectorToLLVM
		MLIRDialect
		MLIRDataLayoutInterfaces
		MLIRCastInterfaces
		MLIRSupport
		MLIRExecutionEngine
		MLIRROCDLToLLVMIRTranslation
		MLIRParser
		MLIRTilingInterface
		MLIRViewLikeInterface
		MLIRVectorToSCF
		MLIRMathToLibm
		MLIRMathToLLVM
		MLIRReconcileUnrealizedCasts
		MLIRRewrite
		MLIRVectorInterfaces
		MLIRTranslateLib
		MLIRCopyOpInterface
		MLIRControlFlowToLLVM
		MLIRControlFlowToLLVM
		MLIRDialectUtils
		MLIRPDLToPDLInterp
		MLIRTransformUtils
		LLVMExtensions
		MLIR

		# Polly
		Polly
		LLVMCore
		LLVMScalarOpts
		LLVMScalarOpts
		LLVMTransformUtils
		LLVMAnalysis
		LLVMipo
		LLVMMC
		LLVMPasses
		LLVMLinker
		LLVMIRReader
		LLVMAnalysis
		LLVMBitReader
		LLVMMCParser
		LLVMObject
		LLVMProfileData
		LLVMTarget
		LLVMVectorize
		LLVMBinaryFormat
		LLVMRemarks
		LLVMAsmParser
		LLVMBitstreamReader
		LLVMAggressiveInstCombine
		LLVMInstCombine
		LLVMBitWriter
		LLVMFrontendOpenMP
		LLVMInstrumentation
		LLVMDebugInfoCodeView
		LLVMTextAPI
		LLVMSymbolize
		LLVMDebugInfoDWARF
		LLVMCoroutines
		LLVMObjCARCOpts
		LLVMDebugInfoPDB
		LLVMDebugInfoMSF

		clangBasic
		clangDriver
		flang-cmake-exports
		flang-libraries
		mlir-cmake-exports
		mlir-cpu-runner
		mlir-headers
		mlir-opt
		mlir-reduce
		mlir-tblgen
		mlir-translate
		mlir_async_runtime
		mlir_c_runner_utils
		mlir_runner_utils
		obj.MLIRCAPIAsync
		obj.MLIRCAPIConversion
		obj.MLIRCAPIDebug
		obj.MLIRCAPIExecutionEngine
		obj.MLIRCAPIFunc
		obj.MLIRCAPIGPU
		obj.MLIRCAPIIR
		obj.MLIRCAPIInterfaces
		obj.MLIRCAPILLVM
		obj.MLIRCAPILinalg
		obj.MLIRCAPIPDL
		obj.MLIRCAPIQuant
		obj.MLIRCAPIRegistration
		obj.MLIRCAPISCF
		obj.MLIRCAPIShape
		obj.MLIRCAPISparseTensor
		obj.MLIRCAPITensor
		obj.MLIRCAPITransforms

		# libraries needed for clang-tblgen
		LLVMDemangle
		LLVMSupport
		LLVMTableGen
		llvm-otool
		llvm-windres
		llvm-debuginfod-find
		llvm-remark-size-diff
		llvm-tli-checker

		# fortran needed for flang
		FortranCommon
		FortranDecimal
		FortranEvaluate
		FortranLower
		FortranParser
		FortranRuntime
		FortranSemantics

		# mlir needed for flang
		mlir-linalg-ods-yaml-gen
		mlir-lsp-server
		bash-autocomplete
		c-index-test

		# clang needed for flang

		# common stuff
		bash-autocomplete
		libclang-python-bindings

		# tools
		c-index-test
		clang
		clang-format
		clang-offload-bundler
		clang-offload-wrapper
		clang-refactor
		clang-repl
		clang-rename
		clang-scan-deps
		diagtool
		hmaptool

		# extra tools
		#clang-apply-replacements
		#clang-change-namespace
		#clang-doc
		#clang-include-fixer
		#clang-move
		#clang-query
		#clang-reorder-fields
		#clang-tidy
		#clang-tidy-headers
		#clangd
		#find-all-symbols
		#modularize
		#pp-trace

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
		clangAnalysisFlowSensitiveModels
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
		clangTooling
		clangToolingASTDiff
		clangToolingCore
		clangToolingInclusions
		clangToolingRefactoring
		clangToolingSyntax
		clangTransformer
		clang-repl
		clangAnalysisFlowSensitive
		libclang-headers
		libclang-python-bindings
		libclang
		diagtool

		# manpages


		clang-check
		clang-extdef-mapping
		scan-build
		scan-build-py
		scan-view

		# f18 needed for flang
		f18-parse-demo
		fir-opt
		FIRBuilder
		FIRCodeGen
		FIRDialect
		FIRSupport
		FIRTransforms
		flang-new
		flangFrontend
		flangFrontendTool
		hmaptool

		# other llvm distribution components
		scan-build-py
		scan-build
		scan-view
		tco
		bbc
		builtins

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

		LLVMgold
		# additional targets
		clang-apply-replacements
		clang-change-namespace
		clang-doc
		clang-include-fixer
		clang-move
		clang-pseudo
		clang-query
		clang-reorder-fields
		clang-tidy-headers
		clang-tidy
		clangd
		compiler-rt
		cxx
		cxxabi
		find-all-symbols
		liblldb
		lld-cmake-exports
		lld
		lldb-argdumper
		lldb-headers
		lldb-instr
		lldb-python-scripts
		lldb-server
		lldb
		lldb-test
		lldb-vscode
		lldbIntelFeatures
		modularize
		openmp
		pp-trace
		runtimes
		unwind

		MLIRComplexToLLVM
		MLIRComplexToLibm
		MLIRComplexToStandard
		MLIRTransformDialectTransforms
		Fortran_main
		arm-common-resource-headers
		tblgen-lsp-server
	)
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
		-DLIBUNWIND_ENABLE_CROSS_UNWINDING=ON
		-DLIBUNWIND_USE_COMPILER_RT=ON
		-DCOMPILER_RT_BUILD_SANITIZERS=ON
		-DLIBCXXABI_ENABLE_SHARED=ON
		-DLIBCXXABI_USE_LLVM_UNWINDER=ON
		-DLIBCXXABI_USE_COMPILER_RT=ON
		-DLIBCXX_CXX_ABI=libcxxabi
		-DLIBCXX_HAS_MUSL_LIBC=$(usex elibc_musl)
		-DLIBCXX_HAS_GCC_S_LIB=OFF
		-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind;compiler-rt;openmp"
                -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;cross-project-tests;flang;libclc;lld;lldb;mlir;polly;pstl"
		-DLLVM_VERSION_SUFFIX="libcxx"
		-DLLVM_ENABLE_LIBCXX=ON
		-DGO_EXECUTABLE=GO_EXECUTABLE-NOTFOUND
		-DLLVM_LIT_ARGS="$(get_lit_flags)"
		-DCMAKE_INSTALL_MANDIR="${EPREFIX}/usr/lib/llvm/${SLOT}/share/man"
		-DLLVM_BUILD_DOCS=${build_docs}
		-DLLVM_ENABLE_OCAMLDOC=OFF
		-DLLVM_ENABLE_SPHINX=${build_docs}
		-DLLVM_ENABLE_DOXYGEN=OFF
		-DLLVM_INSTALL_UTILS=ON
		-DLLVM_BINUTILS_INCDIR="${EPREFIX}"/usr/include
	)

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

	grep -q -E "^CMAKE_PROJECT_VERSION_MAJOR(:.*)?=$(ver_cut 1)$" \
			CMakeCache.txt ||
		die "Incorrect version, did you update _LLVM_MASTER_MAJOR?"
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

	if use polly; then
		DESTDIR=${D} cmake_build tools/polly/install
	fi

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
