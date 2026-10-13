cmake_minimum_required(VERSION 3.20)
project(kde-quickshell-roundcorners LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(QT_MAJOR_VERSION 6)
set(QT_DEFAULT_MAJOR_VERSION 6)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets DBus Quick)
find_package(KF6 REQUIRED COMPONENTS CoreAddons)
find_package(KDecoration3 REQUIRED)
find_package(KWin REQUIRED)

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

kcoreaddons_add_plugin(kdequickshell_roundcorners INSTALL_NAMESPACE "kwin/plugins")
target_sources(kdequickshell_roundcorners PRIVATE main.cpp)
target_link_libraries(kdequickshell_roundcorners KWin::kwin KDecoration3::KDecoration)
