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

## 測試

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --fixed-fps 240 -s res://tests/drive_test.gd
```

## 結構

- `data/motors.json`：馬達常數（WPILib DCMotor）
- `data/robots/`：每台機器人一個設定檔（質量、馬達、齒比、限流、輪胎）
- `sim/physics/`：馬達與電池模型
- `sim/robot/`：swerve 模組、底盤、驅動控制
- `sim/field/`：場地（目前是 2025 的替代場地）
- `cad/sources.json`：Onshape CAD 來源連結
