// fuzz_resource_name.cc: GL resource-name parsing in src/common/utilities.cpp — the
// uniform/attribute/varying name and array-subscript parsers behind glGetUniformLocation,
// glGetProgramResourceIndex and friends, whose strings come straight from (WebGL) callers.
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "common/utilities.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    const std::string name(reinterpret_cast<const char *>(data), size);

    std::vector<unsigned int> subscripts;
    const std::string base = gl::ParseResourceName(name, &subscripts);

    size_t lengthWithoutIndex = 0;
    (void)gl::ParseArrayIndex(name, &lengthWithoutIndex);
    const std::string stripped = gl::StripLastArrayIndex(name);
    (void)gl::IsBuiltInName(name);
    (void)gl::IsBuiltInName(base);
    (void)gl::StripLastArrayIndex(stripped);
    return 0;
}
