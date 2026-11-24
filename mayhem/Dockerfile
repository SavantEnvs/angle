# syntax=docker/dockerfile:1.7
#
# Commit image for ANGLE (savantenvs/angle). Upstream builds with GN + gclient-synced
# third_party trees; this image instead compiles the shader translator, preprocessor, SPIR-V
# helpers and image decoders directly with clang (mayhem/build.sh), so only the two Khronos
# dependencies the translator needs (plus astc-encoder, for the ASTC decoder, and googletest, for
# upstream's unit tests) are cached here, at the revisions pinned in upstream's DEPS.
#
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile --build-arg COMMIT=$(git rev-parse HEAD) -t angle .
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# SPIRV-Headers + SPIRV-Tools at the DEPS pins (third_party/spirv-{headers,tools}/src).
# SPIRV-Tools is built once, uninstrumented, as a static library (angle_spirv_utils.cpp uses it to
# validate the translator's SPIR-V output in ASSERTs).
USER root
ARG SPIRV_HEADERS_REV=fb1379425b16e58dcbdda7be0f8604a7f5cdce78
ARG SPIRV_HEADERS_SHA256=392a1bdee677e72186fa1bebca50231bc66a3c266ea3288a8aec5f2ff61e0074
ARG SPIRV_TOOLS_REV=4a21a48a3840e6e47ded4f1951f7d301b9fc37c3
ARG SPIRV_TOOLS_SHA256=40e2d03b7ee227f2e1920392965fe91fe7d955c17533783181af44a68163061d
RUN set -eux; \
    h=/opt/toolchains/deps/spirv-headers-${SPIRV_HEADERS_REV}; \
    t=/opt/toolchains/deps/spirv-tools-${SPIRV_TOOLS_REV}; \
    mkdir -p "$h/src" "$t/src" /tmp/dep-build; \
    curl -fsSL -o /tmp/h.tgz https://github.com/KhronosGroup/SPIRV-Headers/archive/${SPIRV_HEADERS_REV}.tar.gz; \
    echo "${SPIRV_HEADERS_SHA256}  /tmp/h.tgz" | sha256sum -c -; \
    tar -xzf /tmp/h.tgz --strip-components=1 -C "$h/src"; \
    ln -s src/include "$h/include"; \
    curl -fsSL -o /tmp/t.tgz https://github.com/KhronosGroup/SPIRV-Tools/archive/${SPIRV_TOOLS_REV}.tar.gz; \
    echo "${SPIRV_TOOLS_SHA256}  /tmp/t.tgz" | sha256sum -c -; \
    tar -xzf /tmp/t.tgz --strip-components=1 -C "$t/src"; \
    cmake -S "$t/src" -B /tmp/dep-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-O2 -g -gdwarf-3" -DCMAKE_CXX_FLAGS="-O2 -g -gdwarf-3" \
      -DSPIRV-Headers_SOURCE_DIR="$h/src" -DSPIRV_SKIP_TESTS=ON -DSPIRV_SKIP_EXECUTABLES=ON \
      -DSPIRV_WERROR=OFF -DSPIRV_TOOLS_BUILD_STATIC=ON -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_INSTALL_PREFIX="$t"; \
    ninja -C /tmp/dep-build SPIRV-Tools-static; \
    mkdir -p "$t/lib"; cp /tmp/dep-build/source/libSPIRV-Tools.a "$t/lib/"; \
    cp -r "$t/src/include" "$t/include"; \
    rm -rf /tmp/dep-build /tmp/h.tgz /tmp/t.tgz; chmod -R a+rX "$h" "$t"
# astc-encoder at the DEPS pin (third_party/astc-encoder/src), source only: its decoder is fuzzed
# code (fuzz_load_astc), so build.sh compiles Source/astcenc_*.cpp with the sanitizers, as upstream's
# third_party/astc-encoder/BUILD.gn does (ASTCENC_DECOMPRESS_ONLY=1).
ARG ASTCENC_REV=2319d9c4d4af53a7fc7c52985e264ce6e8a02a9b
ARG ASTCENC_SHA256=8b5068ef28a8db1cb354d89d9cefd19d43eddfc72c3468fce7ebb92b2431d4c4
RUN set -eux; \
    a=/opt/toolchains/deps/astc-encoder-${ASTCENC_REV}; mkdir -p "$a/src"; \
    curl -fsSL -o /tmp/a.tgz https://github.com/ARM-software/astc-encoder/archive/${ASTCENC_REV}.tar.gz; \
    echo "${ASTCENC_SHA256}  /tmp/a.tgz" | sha256sum -c -; \
    tar -xzf /tmp/a.tgz --strip-components=1 -C "$a/src"; rm -f /tmp/a.tgz; chmod -R a+rX "$a"
# googletest at the DEPS pin (third_party/googletest/src), built once uninstrumented as static
# gtest/gmock libraries: build.sh links upstream's angle_unittests compiler, preprocessor, common and
# image_util suites against it (normal flags), and mayhem/test.sh runs them.
ARG GOOGLETEST_REV=a46a6012a133c7c0929fdae55b321c2fe65f3c5f
ARG GOOGLETEST_SHA256=4196454c771aa28bc336b5fde133224cac456d35539c49322912fd2336063b3c
RUN set -eux; \
    g=/opt/toolchains/deps/googletest-${GOOGLETEST_REV}; mkdir -p "$g/src" /tmp/gt-build; \
    curl -fsSL -o /tmp/g.tgz https://github.com/google/googletest/archive/${GOOGLETEST_REV}.tar.gz; \
    echo "${GOOGLETEST_SHA256}  /tmp/g.tgz" | sha256sum -c -; \
    tar -xzf /tmp/g.tgz --strip-components=1 -C "$g/src"; \
    cmake -S "$g/src" -B /tmp/gt-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-O2 -g -gdwarf-3" -DCMAKE_CXX_FLAGS="-O2 -g -gdwarf-3" \
      -DCMAKE_CXX_STANDARD=20 -DBUILD_GMOCK=ON -DINSTALL_GTEST=ON -DCMAKE_INSTALL_PREFIX="$g"; \
    ninja -C /tmp/gt-build install; \
    rm -rf /tmp/gt-build /tmp/g.tgz; chmod -R a+rX "$g"
ENV GOOGLETEST_DIR=/opt/toolchains/deps/googletest-a46a6012a133c7c0929fdae55b321c2fe65f3c5f
ENV ASTCENC_DIR=/opt/toolchains/deps/astc-encoder-2319d9c4d4af53a7fc7c52985e264ce6e8a02a9b
ENV SPIRV_HEADERS_DIR=/opt/toolchains/deps/spirv-headers-fb1379425b16e58dcbdda7be0f8604a7f5cdce78 \
    SPIRV_TOOLS_DIR=/opt/toolchains/deps/spirv-tools-4a21a48a3840e6e47ded4f1951f7d301b9fc37c3

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
