# Unofficial LLVM Overlay
### Experimental gentoo overlay for compiling llvm with additional components
- clang
- [flang/f18](https://github.com/llvm/llvm-project/tree/main/flang#flang)
- polly
- mlir
- openmp
- libcxx(abi)
- lld
- libunwind
##### To add this overlay:
```
# eselect repository add LinuxUserGD git https://github.com/LinuxUserGD/linuxuser-flang-overlay.git
# emerge --sync LinuxUserGD
```
##### [https://wiki.gentoo.org/wiki/Eselect/Repository#Add_repositories](https://wiki.gentoo.org/wiki/Eselect/Repository#Add_repositories)
