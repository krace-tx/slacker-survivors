#!/usr/bin/env bash
# ==============================================================================
# Industrial Blender 3D Asset Pipeline Gate (run_pipeline_gate.sh)
# ==============================================================================
# 一键串联执行：
#   1. Execute  : 运行 Blender 参数化构建脚本生成 .blend 与 .glb
#   2. Verify   : 运行 verify_blender_asset.py 检验网格、骨骼权重、AABB 与 GLB 二进制头
#   3. Deliver  : 运行 Godot 4 Headless 验证 .glb 导入与全工程 GDScript 零编译错误
#
# 用法:
#   bash .agents/skills/blender-pipeline/scripts/run_pipeline_gate.sh \
#     <build_script.py> <output.blend> <output.glb> [--render-views]
# ==============================================================================

set -euo pipefail

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <build_script.py> <output.blend> <output.glb> [--render-views]"
    exit 1
fi

BUILD_SCRIPT="$1"
BLEND_FILE="$2"
GLB_FILE="$3"
EXTRA_FLAG="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/verify_blender_asset.py"
RENDER_OUT_DIR="$(dirname "$BLEND_FILE")/renders"

BLENDER_BIN="/Applications/Blender.app/Contents/MacOS/Blender"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"

echo "🚀 [Stage 1/3] 执行 Blender 参数化资产构建脚本: $BUILD_SCRIPT"
"$BLENDER_BIN" --background --python "$BUILD_SCRIPT"

echo "🔍 [Stage 2/3] 运行 Blender 3D 资产结构与骨骼权重断言: $BLEND_FILE"
if [ "$EXTRA_FLAG" = "--render-views" ]; then
    "$BLENDER_BIN" --background "$BLEND_FILE" --python "$VERIFY_SCRIPT" -- \
        --output-dir "$RENDER_OUT_DIR" \
        --expected-glb "$GLB_FILE" \
        --render-views
else
    "$BLENDER_BIN" --background "$BLEND_FILE" --python "$VERIFY_SCRIPT" -- \
        --output-dir "$RENDER_OUT_DIR" \
        --expected-glb "$GLB_FILE"
fi

echo "🎮 [Stage 3/3] 运行 Godot 4 Headless 资源导入与静态编译检查"
cd "$PROJECT_ROOT"
"$GODOT_BIN" --headless --editor --quit

echo "✅ [Pipeline Gate Passed] 3D 资产构建、结构质检与 Godot 导入验证全部通过！"
