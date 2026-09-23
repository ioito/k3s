#!/bin/bash
# k3s riscv64 发布资产组装/发布脚本（对齐官方 k3s-io/k3s releases 资产格式）
#
# 用法:
#   ./scripts/release-riscv64.sh                  # 组装资产到 dist/artifacts
#   ./scripts/release-riscv64.sh --publish        # 组装 + 打 tag + gh release create
#
# 产物（与官方 v1.28.15+k3s1 release 资产对应）:
#   k3s-riscv64                          # riscv64 二进制（同官方 amd64 的 "k3s" 命名规则）
#   k3s-airgap-images-riscv64.tar        # airgap 镜像 tar（同官方）
#   k3s-airgap-images-riscv64.tar.gz     # 同上，gzip 版
#   k3s-airgap-images-riscv64.tar.zst    # 同上，zstd 版
#   k3s-images.txt                       # airgap 镜像清单
#   sha256sum-riscv64.txt                # 本架构资产校验和（同官方 sha256sum-<arch>.txt）
#
# 发布说明:
#   - 默认跳过二进制重编，复用 dist/artifacts 已有 k3s-riscv64（版本号含 -dirty 时，
#     先 git tag 指向 HEAD 再 ./scripts/build + ./scripts/package 重编，得到干净版本号）；
#   - --publish 需 gh CLI 已登录，且仓库已 push（tag 建议 v1.28.15+k3s-riscv64.1 这类格式）。
set -e

cd "$(dirname "$0")/.."
. ./scripts/version.sh

export ARCH=riscv64
DIST=dist/artifacts
mkdir -p "${DIST}"

ASSETS=()

# 1) 二进制：已有则复用，否则构建
BIN="${DIST}/k3s-riscv64"
if [ -f "${BIN}" ]; then
    echo "[release] 复用二进制: ${BIN} ($(/usr/bin/file -b "${BIN}" 2>/dev/null | cut -d, -f1))"
else
    echo "[release] 未找到 ${BIN}，执行 ./scripts/package 构建..."
    ./scripts/package
    [ -f "${BIN}" ] || { echo "构建产物不在 ${BIN}，请检查 OUT 环境"; exit 1; }
fi
ASSETS+=("${BIN}")

# 2) airgap 包：已有则复用，否则生成
AIRGAP="${DIST}/k3s-airgap-images-riscv64.tar.gz"
if [ -f "${AIRGAP}" ]; then
    echo "[release] 复用 airgap 包: ${AIRGAP}"
else
    echo "[release] 生成 airgap 包..."
    ./scripts/package-airgap-riscv64
fi
ASSETS+=("${DIST}/k3s-airgap-images-riscv64.tar")
ASSETS+=("${DIST}/k3s-airgap-images-riscv64.tar.gz")
ASSETS+=("${DIST}/k3s-airgap-images-riscv64.tar.zst")

# 3) 镜像清单
IMGLIST="${DIST}/k3s-images.txt"
cat > "${IMGLIST}" <<'EOF'
docker.io/rancher/local-path-provisioner:v0.0.30
docker.io/rancher/mirrored-coredns-coredns:1.11.3
docker.io/rancher/mirrored-library-busybox:1.36.1
docker.io/rancher/mirrored-library-traefik:2.11.10
docker.io/rancher/mirrored-pause:3.6
EOF
ASSETS+=("${IMGLIST}")

# 4) 校验和（同官方 sha256sum-<arch>.txt）
SHAFILE="${DIST}/sha256sum-riscv64.txt"
: > "${SHAFILE}"
for f in "${ASSETS[@]}"; do
    (cd "${DIST}" && sha256sum "$(basename "${f}")") >> "${SHAFILE}"
done
echo "[release] 校验和: ${SHAFILE}"
cat "${SHAFILE}"

# 5) 可选发布
if [ "$1" = "--publish" ]; then
    command -v gh >/dev/null || { echo "缺少 gh CLI"; exit 1; }
    TAG=$(git tag -l --contains HEAD | head -n 1)
    if [ -z "${TAG}" ]; then
        echo "HEAD 无 tag 指向，请先: git tag v1.28.15+k3s-riscv64.1 && git push origin <tag>"
        exit 1
    fi
    echo "[release] gh release create ${TAG} ..."
    gh release create "${TAG}" "${ASSETS[@]}" --repo "$(git config --get remote.origin.url | sed 's#.*github.com[:/]##; s#\.git$##')" \
        --title "${TAG} (riscv64)" --notes "k3s riscv64 发布（含 airgap 镜像包），基于 v1.28.15+k3s1。"
    echo "[release] 发布完成: https://github.com/$(git config --get remote.origin.url | sed 's#.*github.com[:/]##; s#\.git$##')/releases/tag/${TAG}"
fi
