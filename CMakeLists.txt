cmake_minimum_required(VERSION 3.0)
project(DotWriter)

include(GNUInstallDirs)

set(FILES
    "lib/AttributeSet.cpp"
    "lib/Cluster.cpp"
    "lib/Edge.cpp"
    "lib/Enums.cpp"
    "lib/Graph.cpp"
    "lib/IdManager.cpp"
    "lib/Node.cpp"
    "lib/RootGraph.cpp"
    "lib/Subgraph.cpp"
    "lib/Util.cpp"
)

add_library(${PROJECT_NAME} STATIC ${FILES})
set_target_properties(${PROJECT_NAME} PROPERTIES
    PUBLIC_HEADER "lib/DotWriter.h"
    OUTPUT_NAME "dotwriter"
    CXX_STANDARD              14
    CXX_STANDARD_REQUIRED     YES
    CXX_EXTENSIONS            NO
)

target_include_directories(${PROJECT_NAME} INTERFACE 
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib>
)

install(TARGETS ${PROJECT_NAME}
    DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION build/
    PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)
