# The shell's own Breeze window decoration: Breeze's sources as build.sh
# fetched and patched them, built under a name of its own next to the
# installed Breeze. It reads Breeze's settings (breezerc) and uses its
# settings page.
cmake_minimum_required(VERSION 3.20)
project(kde-quickshell-breeze LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(QT_MAJOR_VERSION 6)
set(QT_DEFAULT_MAJOR_VERSION 6)

set(BREEZE_SOURCE_DIR "" CACHE PATH "Breeze's sources with rounded.patch applied (build.sh)")
if(NOT EXISTS "${BREEZE_SOURCE_DIR}/kdecoration/breezedecoration.cpp")
    message(FATAL_ERROR "BREEZE_SOURCE_DIR is not a Breeze source tree; run build.sh")
endif()

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets DBus)
find_package(KF6 REQUIRED COMPONENTS ColorScheme Config CoreAddons GuiAddons I18n IconThemes)
find_package(KDecoration3 REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN="breeze_kwin_deco")

set(decoration ${BREEZE_SOURCE_DIR}/kdecoration)
set(common ${BREEZE_SOURCE_DIR}/libbreezecommon)

set(breezedecoration_SRCS
    ${decoration}/breezebutton.cpp
    ${decoration}/breezedecoration.cpp
    ${decoration}/breezesettingsprovider.cpp
    ${decoration}/breezeexceptionlist.cpp
    ${common}/breezeboxshadowrenderer.cpp
)
kconfig_add_kcfg_files(breezedecoration_SRCS ${decoration}/breezesettings.kcfgc)

add_library(breezedecoration MODULE ${breezedecoration_SRCS})
target_include_directories(breezedecoration PRIVATE ${decoration} ${common})
set_target_properties(breezedecoration PROPERTIES
    OUTPUT_NAME io.github.mak1a4.kde-quickshell.breeze
    PREFIX ""
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/org.kde.kdecoration3
)
target_link_libraries(breezedecoration PRIVATE
    Qt6::DBus
    Qt6::Widgets
    KF6::ColorScheme
    KF6::ConfigGui
    KF6::CoreAddons
    KF6::GuiAddons
    KF6::I18n
    KF6::IconThemes
    KDecoration3::KDecoration
)
