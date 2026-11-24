// gtest main for upstream's angle_unittests sources that mayhem/build.sh builds (compiler,
// preprocessor, src/common and src/image_util suites). It does what src/tests/angle_unittest_main.cpp
// does — sh::Initialize()/sh::Finalize() around the run — without upstream's TestSuite runner
// (src/tests/test_utils/runner), which pulls in util/ and rapidjson; plain gtest output
// (--gtest_output=json) is what mayhem/test.sh reads.
#include "GLSLANG/ShaderLang.h"
#include "gtest/gtest.h"

namespace
{
class CompilerTestEnvironment : public testing::Environment
{
  public:
    void SetUp() override { ASSERT_TRUE(sh::Initialize()) << "Failed to initialize the compiler."; }
    void TearDown() override { ASSERT_TRUE(sh::Finalize()) << "Failed to finalize the compiler."; }
};
}  // namespace

// Also defined by upstream's main (test_utils_unittest_helper reads it).
bool gVerbose = false;

int main(int argc, char **argv)
{
    testing::InitGoogleTest(&argc, argv);
    testing::AddGlobalTestEnvironment(new CompilerTestEnvironment());
    return RUN_ALL_TESTS();
}
