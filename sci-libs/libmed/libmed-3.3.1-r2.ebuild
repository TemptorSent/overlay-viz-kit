# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6
#CMAKE_IN_SOURCE_BUILD=1

FORTRAN_NEEDED=fortran
# NOTE:The build for multiple python versions should be possible but complecated for the build system
PYTHON_COMPAT=( python2_7 python3_{3,4,5,6,7} )

inherit eutils toolchain-funcs fortran-2 python-single-r1 python-utils-r1 cmake-utils

HDF5_18_PV="1.8.21"
HDF5_18_P="hdf5-${HDF5_18_PV}"

DESCRIPTION="Med File library. (with HDF5-1.8)"
HOMEPAGE="http://salome-platform.org"
MED_SRC_URI="http://files.salome-platform.org/Salome/other/${P#lib}.tar.gz"
HDF5_18_SRC_URI="https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8/${HDF5_18_P}/src/CMake-${HDF5_18_P}.tar.gz"

SRC_URI="${MED_SRC_URI} ${HDF5_18_SRC_URI}"

PATCHES=(
	"${FILESDIR}/${P}-cmake-fortran.patch"
	"${FILESDIR}/${P}-disable-python-compile.patch"
	"${FILESDIR}/${P}-mpi.patch"
	"${FILESDIR}/${P}-swig.patch"
	#"${FILESDIR}/${P}-hdf5-1.10-support.patch"  # This breaks file compatibility -- which means we may have to have multiple libmed versions :(
	"${FILESDIR}/${P}-cmakelist.patch"
	"${FILESDIR}/${P}-tests.patch"
	"${FILESDIR}/${P}-tests-python3.patch"
)


LICENSE="GPL-3 LGPL-3"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE="+doc +fortran +python mpi static-libs test"

REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

RDEPEND="
	=sci-libs/hdf5-1.8*[fortran=,mpi=]
	mpi? ( virtual/mpi[fortran=] )
	python? ( ${PYTHON_DEPS} )
"

DEPEND="${RDEPEND}
	python? ( >=dev-lang/swig-2.0.9:0 )
"

S="${WORKDIR}/${P#lib}_SRC"

DOCS=( AUTHORS COPYING COPYING.LESSER ChangeLog NEWS README TODO )

pkg_setup() {
	use python && python-single-r1_pkg_setup
	use fortran && fortran-2_pkg_setup
}

src_prepare() {
	# Link hdf5 source dir in
	ln -snf ../"CMake-${HDF5_18_P}/${HDF5_18_P}"

	sed -e '/MED_FIND_HDF5()/ {
i\
IF(MEDFILE_USE_SYSTEM_HDF5)
a\
ELSE()\
    SET(HDF5_EXTERNALLY_CONFIGURED 1)\
    SET(HDF5_EXTERNAL_LIB_PREFIX "medfile")\
    SET(HDF5_EXPORTED_TARGETS "medfileTargets")\
    SET(H5_ENABLE_STATIC_LIB YES)\
    SET(H5_ENABLE_SHARED_LIB NO)\
    SET(BUILD_SHARED_LIBS NO)\
    SET(BUILD_TESTING NO)\
    SET(HDF5_BUILD_TOOLS NO)\
    SET(HDF5_BUILD_EXAMPLES NO)\
    SET(HDF5_BUILD_HL_LIB NO)\
\
ADD_SUBDIRECTORY('"${HDF5_18_P}"')\
ENDIF()
c\
    MED_FIND_HDF5()
		}' -i ./CMakeLists.txt

	# fixes for correct libdir name
	sed -i -e "s@SET(_install_dir lib/python@SET(_install_dir $(get_libdir)/python@" \
		./python/CMakeLists.txt || die "sed failed"
	for cm in ./src/CMakeLists.txt ./tools/medimport/CMakeLists.txt
	do
		sed -i -e "s@INSTALL(TARGETS \(.*\) DESTINATION lib)@INSTALL(TARGETS \1 DESTINATION $(get_libdir))@" \
			"${cm}" || die "sed on ${cm} failed"
	done

	cmake-utils_src_prepare
}

# WHISKEY-TANGO-FOXTROT: med uses autotools configure script to build CMakeLists.txt from CMakeLists.txt.in?!?
src_configure() {
	local myconf=(
		--with-pic
		--with-swig
		--with-med_int=int
		--with-int64=__int64_t
	)
	#econf "${myconf[@]}" PYTHON_LDFLAGS="$(python_get_LIBS)" PYTHON_VERSION="${EPYTHON#python}" LDFLAGS="${LDFLAGS} $(python_get_LIBS)" CFLAGS="${CFLAGS} $(python_get_CFLAGS)"


	local mycmakeargs=(
		-DCMAKE_SKIP_RPATH=NO
		-DCMAKE_SKIP_INSTALL_RPATH=YES
		-DMEDFILE_BUILD_STATIC_LIBS="$(usex static-libs)"
		-DMEDFILE_BUILD_FORTRAN="$(usex fortran)"
		-MEDFILE_USE_MPI=$(usex mpi)
		-DMEDFILE_BUILD_TESTS=$(usex test)
		-DMEDFILE_INSTALL_DOC=$(usex doc)
		-DMEDFILE_BUILD_PYTHON=$(usex python)
	)

	if use mpi; then
		export CC=mpicc
		export CXX=mpicxx
		export FC=mpif90
		export F90=mpif90
		export F77=mpif77
	fi

	cmake-utils_src_configure
}

src_install() {
	cmake-utils_src_install

	# the optimization done in CMakeLists.txt has been disabled so
	# we need to do it manually
	use python && python_optimize

	# Remove documentation
	! use doc && rm -rf "${D}/usr/share/doc"

	# Prevent test executables being installed
	use test && rm -rf "${D}/usr/bin/"{testc,testf,usescases}
}

src_test() {
	# override parallel mode only for tests
	local myctestargs=(
		"-j 1"
	)
	cmake-utils_src_test
}
