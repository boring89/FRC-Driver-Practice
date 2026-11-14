# FRC Driver Practice

以真實物理為目標的 FRC 駕駛練習模擬器（Godot 4 + Jolt）。

## 執行

Godot 4.7 放在 `tools/godot/`（不進版控）。第一次或新增腳本後先匯入一次：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --import
```

開始練習：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path .
```

左搖桿 / WASD 移動，右搖桿 / Q E 旋轉，Start / R 重置，Back / C 切換視角。
機構預設姿勢用數字鍵（依設定檔裡的順序）或設定檔指定的手把按鍵切換。

## 場地（從 Onshape CAD 建置）

場地模型不進版控，要從 Onshape 匯出後在 Blender 處理一次。金鑰放在 `.env`
（`ONSHAPE_ACCESS_KEY`、`ONSHAPE_SECRET_KEY`），每次匯出會消耗 API 額度。

```bash
scripts/onshape.py gltf "$(python3 -c "import json; print(json.load(open('cad/sources.json'))['2025']['field'])")" cad/export/2025/field.glb
```

```bash
blender -b -P scripts/build_field.py -- cad/export/2025/field.glb data/fields/2025.json assets/fields/2025
```

之後重新匯入一次（上面的 `--import`）。沒有建置場地時，模擬器會改用簡化的替代場地。

## 機器人（從 Onshape CAD 建置）

機器人模型同樣不進版控。把 Onshape 匯出的 GLB 放到 `cad/export/<年份>/<隊號>/robot.glb`
（企業帳號的文件 API 讀不到，要從網頁的分頁右鍵 Export 匯出），再建置：

```bash
blender -b -P scripts/build_robot.py -- cad/export/2025/2910/robot.glb data/robots/2910_2025.json assets/robots/2910_2025
```

之後重新匯入一次。機器人設定檔的 `cad` 區塊決定哪些零件要丟掉、哪些組裝是可動的連桿。
沒有建置模型時，機器人會用方塊替代外觀。

## 測試

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --fixed-fps 240 -s res://tests/drive_test.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --fixed-fps 240 -s res://tests/field_test.gd
```

機構測試（需要先建置機器人模型）：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --fixed-fps 240 -s res://tests/mechanism_test.gd
```

駕駛測試可以指定機器人設定檔：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --fixed-fps 240 -s res://tests/drive_test.gd -- res://data/robots/2910_2025.json
```

## 結構

- `data/motors.json`：馬達常數（WPILib DCMotor）
- `data/robots/`：每台機器人一個設定檔（質量、馬達、齒比、限流、輪胎）
- `sim/physics/`：馬達與電池模型
- `sim/robot/`：swerve 模組、底盤、驅動控制、機構（關節與上層結構）
- `sim/field/`：場地（CAD 場地與替代場地）
- `data/fields/`：每年場地的處理設定（座標、要移除的遊戲物件、材質）
- `scripts/`：Onshape 匯出與 Blender 場地建置
- `cad/sources.json`：Onshape CAD 來源連結
