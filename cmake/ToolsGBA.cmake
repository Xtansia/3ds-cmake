if(NOT GBA)
    message(WARNING "Those tools can only be used if you are using the GBA toolchain file. Please erase this build directory or create another one, and then use -DCMAKE_TOOLCHAIN_FILE=DevkitArmGBA.cmake when calling cmake for the 1st time. For more information, see the Readme.md for more information.")
endif()

get_filename_component(__toolsgbadir ${CMAKE_CURRENT_LIST_FILE} PATH) # Used to locate files to be used with configure_file

message(STATUS "Looking for GBA tools...")

#############
## OBJCOPY ##
#############
if(NOT OBJCOPY)
    # message(STATUS "Looking for objcopy...")
    find_program(OBJCOPY arm-none-eabi-objcopy ${DEVKITARM}/bin)
    if(OBJCOPY)
        message(STATUS "objcopy: ${OBJCOPY} - found")
    else()
        message(WARNING "objcopy - not found")
    endif()
endif()

#############
##  STRIP  ##
#############
if(NOT STRIP)
    # message(STATUS "Looking for strip...")
    find_program(STRIP arm-none-eabi-strip ${DEVKITARM}/bin)
    if(STRIP)
        message(STATUS "strip: ${STRIP} - found")
    else()
        message(WARNING "strip - not found")
    endif()
endif()

#############
##  BIN2S  ##
#############
if(NOT BIN2S)
    # message(STATUS "Looking for bin2s...")
    find_program(BIN2S bin2s ${DEVKITARM}/bin)
    if(BIN2S)
        message(STATUS "bin2s: ${BIN2S} - found")
    else()
        message(WARNING "bin2s - not found")
    endif()
endif()

############
## GBAFIX ##
############
if(NOT GBAFIX)
    # message(STATUS "Looking for gbafix...")
    find_program(GBAFIX gbafix ${DEVKITARM}/bin)
    if(GBAFIX)
        message(STATUS "gbafix: ${GBAFIX} - found")
    else()
        message(WARNING "gbafix - not found")
    endif()
endif()

############
## MMUTIL ##
############
if(NOT MMUTIL)
    # message(STATUS "Looking for mmutil...")
    find_program(MMUTIL mmutil ${DEVKITARM}/bin)
    if(MMUTIL)
        message(STATUS "mmutil: ${MMUTIL} - found")
    else()
        message(WARNING "mmutil - not found")
    endif()
endif()

###################
### EXECUTABLES ###
###################

# Build .elf and .gba file from binary target
# binaryTarget: Name of CMake target generating the binary file
# title: Game title, 12 uppercase chars
# gameCode: Game code, 4 uppercase chars
# makeCode: Maker code, 2 uppercase chars
# version: Version byte [0,255]
# See: https://github.com/devkitPro/gba-tools and: http://problemkaputt.de/gbatek-gba-cartridge-header.htm
function(add_gba_executables binaryTarget gameTitle gameCode makerCode version)
    set(binFile $<TARGET_FILE:${binaryTarget}>)
    get_filename_component(binBasePath ${binFile} NAME_WE)
    set(elfFile ${binBasePath}.elf)
    add_custom_command(TARGET ${binaryTarget} POST_BUILD
        COMMAND
            ${CMAKE_COMMAND} -E copy "${binFile}" "${elfFile}"
        VERBATIM
    )
    set(gbaFile ${binBasePath}.gba)
    add_custom_command(TARGET ${binaryTarget} POST_BUILD
        COMMAND
            ${OBJCOPY} -O binary "${binFile}" "${gbaFile}"
        COMMAND
            ${GBAFIX} "${gbaFile}" -p -t${gameTitle} -c${gameCode} -m${makerCode} -r${version}
        VERBATIM
    )
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES ${elfFile})
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES ${gbaFile})
endfunction()

# Build .map file for binary target
# binaryTarget: Name of CMake target generating the binary file
function(add_map_file binaryTarget)
    set(binFile $<TARGET_FILE:${binaryTarget}>)
    get_filename_component(binBasePath ${binFile} NAME_WE)
    set(mapFile ${binBasePath}.map)
    set_target_properties(${binaryTarget} PROPERTIES LINK_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-Map=${binaryTarget}.map")
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES ${mapFile})
endfunction()

# Build section analysis file for binary target
# binaryTarget: Name of CMake target generating the binary file
function(add_sections_file binaryTarget)
    set(binFile $<TARGET_FILE:${binaryTarget}>)
    get_filename_component(binBasePath ${binFile} NAME_WE)
    set(analysisFile ${binBasePath}_sections.md)
    find_file(convert_nm_sysv_to_md
        NAMES
            convert_nm_sysv_to_md.cmake
        PATHS
            ${CMAKE_MODULE_PATH}
        NO_CMAKE_FIND_ROOT_PATH
        REQUIRED
    )
    add_custom_command(TARGET ${binaryTarget} POST_BUILD
        COMMAND
            ${CMAKE_NM} --format=sysv --numeric-sort --demangle=auto "${binFile}" > "${analysisFile}"
        VERBATIM
        COMMAND
            cmake -P "${convert_nm_sysv_to_md}" "${analysisFile}" "${analysisFile}"
        VERBATIM
    )
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES ${analysisFile})
endfunction()

######################
### File embedding ###
######################

macro(add_binary_library libtarget)
    if(NOT ${ARGC} GREATER 1)
        message(FATAL_ERROR "add_binary_library : Argument error (no input files)")
    endif()
    get_cmake_property(ENABLED_LANGUAGES ENABLED_LANGUAGES)
    if(NOT ENABLED_LANGUAGES MATCHES ".*ASM.*")
        message(FATAL_ERROR "You have to enable ASM in order to use add_binary_library (or any target_embed_* which relies on it). Use enable_language(ASM) in your CMakeLists. Currently enabled languages are ${ENABLED_LANGUAGES}")
    endif()
    foreach(__file ${ARGN})
        get_filename_component(__file_wd ${__file} NAME)
        string(REGEX REPLACE "^([0-9])" "_\\1" __BIN_FILE_NAME ${__file_wd}) # add '_' if the file name starts by a number
        string(REGEX REPLACE "[-./]" "_" __BIN_FILE_NAME ${__BIN_FILE_NAME})
        #Generate the header file
        configure_file(${__toolsgbadir}/bin2s_header.h.in ${CMAKE_CURRENT_BINARY_DIR}/${libtarget}_include/${__BIN_FILE_NAME}.h)
    endforeach()
    file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/binaries_asm)
    # Generate the assembly file, and create the new target
    add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/binaries_asm/${libtarget}.s
        COMMAND ${BIN2S} ${ARGN} > ${CMAKE_CURRENT_BINARY_DIR}/binaries_asm/${libtarget}.s
        DEPENDS ${ARGN}
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    )
    add_library(${libtarget} ${CMAKE_CURRENT_BINARY_DIR}/binaries_asm/${libtarget}.s)
    target_include_directories(${libtarget} INTERFACE ${CMAKE_CURRENT_BINARY_DIR}/${libtarget}_include)
endmacro()

macro(target_embed_file _target)
    if(NOT ${ARGC} GREATER 1)
        message(FATAL_ERROR "target_embed_file : Argument error (no input files)")
    endif()
    get_filename_component(__1st_file_wd ${ARGV1} NAME)
    add_binary_library(__${_target}_embed_${__1st_file_wd} ${ARGN})
    target_link_libraries(${_target} __${_target}_embed_${__1st_file_wd})
endmacro()

######################
###     MaxMOD     ###
######################

macro(target_maxmod_file _target)
    if(NOT ${ARGC} GREATER 1)
        message(FATAL_ERROR "target_maxmod_file : Argument error (no input files)")
    endif()
    set(BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR}/mm_soundbank)
	set(__BIN_FILE_NAME "soundbank_bin")
	configure_file(${__toolsgbadir}/bin2s_header.h.in ${BUILD_DIR}/soundbank_bin.h)
    add_custom_command(OUTPUT ${BUILD_DIR}/soundbank.bin.o ${BUILD_DIR}/soundbank.bin ${BUILD_DIR}/soundbank.h
        COMMAND ${MMUTIL} ${ARGN} -o${BUILD_DIR}/soundbank.bin -h${BUILD_DIR}/soundbank.h
        COMMAND ${BIN2S} ${BUILD_DIR}/soundbank.bin | ${CMAKE_AS} -o ${BUILD_DIR}/soundbank.bin.o
        DEPENDS ${ARGN}
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    )
    add_custom_target(mm_soundbank
        DEPENDS ${BUILD_DIR}/soundbank.bin.o
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    )
    set_target_properties(mm_soundbank PROPERTIES LINKER_LANGUAGE C)
	include_directories(${BUILD_DIR})
    add_dependencies(${_target} mm_soundbank)
	target_link_libraries(${_target} ${BUILD_DIR}/soundbank.bin.o)
endmacro()
