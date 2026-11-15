# FRC Driver Practice

以真實物理為目標的 FRC 駕駛練習模擬器（Godot 4 + Jolt）。

## 執行

Godot 4.7 放在 `tools/godot/`（不進版控）。第一次或新增腳本後先匯入一次：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --import
```

啟動（會先進標題選單，選賽季和機器人；按 Play 進入比賽設定，選聯盟、在場地圖上拖曳決定起始位置、
選計時比賽或自由練習、比賽長度和 coral 補給方式；Settings 裡可以調畫質和鍵位）：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path .
```

預設鍵位（鍵盤 / 手把），都能在 Settings 的 Keybinds 分頁重新綁定，設定存在 `user://settings.cfg`：

| 動作 | 鍵盤 | 手把 |
|---|---|---|
| 移動 | W A S D | 左搖桿 |
| 旋轉 | J / L | 右搖桿 |
| 自動對位左 / 右樹枝（駕駛視角） | Q / E | LB / RB |
| L1 / L2 / L3 / L4 | U / I / O / P | A / B / X / Y |
| Intake（按住吸入，並切到吸取姿勢） | Shift | LT |
| Place（送出得分） | K | RT |
| 切換 coral / algae 模式 | ; | 十字鍵上 |
| Robot Special（station 取 coral / HP 取 algae） | V | 十字鍵右 |
| Stow | Z | 十字鍵下 |
| Climb（每按一次進到下一段） | C | 十字鍵左 |
| 切換視角 | Space | 按下右搖桿 |
| 行駛速度 40% / 70% / 100% | 1 / 2 / 3 | |
| Station 手動送出一個 coral | H | Back |
| 再預載一個 coral（開場和重置時會自動預載） | B | |
| 重置 | R | Start |

Esc 回標題選單。每個按鍵在各模式下對應哪個姿勢，寫在機器人設定檔的 `controls` 區塊。
按 L1–L4 時會看車頭朝向：車頭朝著最近的 reef 就用正面姿勢，車尾朝著 reef 且機器人有對應的
背向姿勢（`controls.<模式>.back`）就用背向姿勢；自動對位會維持那個朝向。
自動對位的左右以駕駛看出去的方向為準，所以 reef 背面的左右和面對那一面時相反；algae 模式下
自動對位會對到那一面的正中間（reef 上的 algae 在兩根樹枝中間）。

`controls.pickup` 列出的是「取物姿勢」（reef 上的 algae、station 取 coral、HP 取 algae）：在這些
姿勢下手上沒東西時滾輪會自己轉，不用按 Intake。coral 模式下手上沒有 coral 時按 L2 / L3 會自動切到
algae 模式去拿 reef 上的 algae，把那顆 algae 放出去（net / processor）之後自動切回 coral 模式；
還沒拿到就按 Stow 也會切回來。用按鍵手動切到 algae 模式的話不會自動切回。

Intake 只吸目前模式的遊戲物件（coral 模式不會吸 algae，反之亦然），也不會把已經放在 reef 上的
coral 吸回來。己方兩個 coral station 的 human player 會自動補 coral：地上散落的 coral 少於上限
（預設 4 個，比賽設定的 Coral feed 可選 2 / 4 / 6 或 manual 關閉）時每 1.5 秒丟一個，丟到附近比較
少的那個 station，到上限就停；立著的 staged coral 和 reef 上的不算。

拿著的遊戲物件固定在 end effector 上跟著機構走。End effector 的碰撞是每個零件各一個凸包，放在
獨立的碰撞體上：它會推動、擋住 coral 和 algae，但會穿過場地（reef、牆），因為機構是照位置硬帶的，
讓它去頂場地只會把整台車推開。手臂其他連桿仍然會和場地碰撞。

畫面上只有底部的比分和比賽時間。計時比賽預設 2:15（teleop，長度可在比賽設定裡改），最後 20 秒是
endgame，時間到機器人會停止回應，按重置開始新的一場；自由練習不倒數，只計分和已經過的時間。分數依場上當下的狀態計算：coral 掛在 reef 樹枝上 L2 / L3 / L4 各 3 / 4 / 5 分
（每根樹枝只算一個）、躺在 trough 裡 2 分，algae 停在 net 裡 4 分、送出 processor 6 分。
藍方 reef 算藍方的分數，紅方 reef 算紅方。分數和位置寫在 `data/fields/<年份>.json` 的 `match` 區塊。
按 F3 顯示除錯資訊（速度、電池、關節角度、鍵位提示）。

按 Tab 開啟姿勢編輯器：用滑桿直接擺每個關節，右鍵拖曳環繞視角、滾輪縮放，
「Save preset」會把目前姿勢存進該機器人的預設姿勢檔（`data/robots/*_presets.json`）。

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

之後重新匯入一次。機器人設定檔的 `cad` 區塊決定哪些零件要丟掉、哪些組裝是可動的連桿；連桿規則加上
`"collision": "parts"` 會替它每個較大的零件各算一個碰撞凸包（寫進 `model.json` 的 `part_hulls`），
而不是整個連桿一個凸包。`mechanism` 裡連桿的 `"collides": "pieces"` 表示它只和遊戲物件碰撞。
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

遊戲物件與 intake 測試：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --fixed-fps 240 -s res://tests/game_piece_test.gd
```

開場與重置測試（預載 coral、回到 coral 模式）：

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --fixed-fps 240 -s res://tests/session_test.gd
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
- `sim/field/`：場地（CAD 場地與替代場地）、遊戲物件
- `sim/match/`：比賽計時與計分
- `sim/menu/`：標題選單與設定畫面；`sim/settings.gd` 是設定的讀寫與套用
- `data/fields/`：每年場地的處理設定（座標、要移除的遊戲物件、材質）
- `scripts/`：Onshape 匯出與 Blender 場地建置
- `cad/sources.json`：Onshape CAD 來源連結
