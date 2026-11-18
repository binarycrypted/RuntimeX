# RuntimeX
In-game iOS Reverse Engineering Console &amp; Custom Scripting Language (HexLang 2.0) featuring a Mach-VM Int/Float Memory Scanner, Dynamic ObjC Runtime Hooker, Speedhack, and Bilingual Settings Panel.


# RuntimeX & HexLang 2.0

![Platform](https://shields.io)
![Language](https://shields.io)
![License](https://shields.io)

**RuntimeX** is a lightweight, standalone in-game reverse engineering console, memory patcher, and custom scripting engine (**HexLang 2.0**) built for 32-bit iOS (`armv7` / iOS 9.3.6). It injects a draggable cyberpunk HUD overlay directly into target applications with native Settings integration (`PreferenceLoader`), real-time Mach-VM memory scanning (`int32` & `float32`), Objective-C runtime method swizzling, and a kernel-level `gettimeofday` speedhack engine.

---

## Key Features

- **Native Settings Panel (`Settings -> RuntimeX`)**:
  - Master toggle (`Enable RuntimeX`) without uninstalling the package.
  - Smart app filter (`Hide in System Apps com.apple.*`) so the HUD stays out of system utilities.
  - `Auto-Run` mode: automatically executes `/var/mobile/Documents/autorun.hex` on target app launch.
  - Bilingual UI switch (`English` / `Русский`) that dynamically localizes both the Settings bundle and the in-game console.
  - 3 Cyberpunk HUD themes (`Matrix Green`, `Cyberpunk Neon`, `Hacker Amber`).
- **HexLang 2.0 Custom Scripting Engine**:
  - Variables (`let`), arithmetic (`+`, `-`, `*`, `/`), string concatenation, comments (`#`), and `if` conditional blocks.
  - Synchronous loops (`repeat N { ... }`) and asynchronous background timers (`every SEC { ... }`).
  - Direct Mach-VM virtual memory scanning, filtering, hex address dumping (`mem.list`), writing, and freezing (`int32` & `float32`).
  - Live Objective-C Runtime class/method discovery (`objc.find`, `objc.methods`) and dynamic return-value swizzling (`objc.hook`).
  - Time dilation / Speedhack engine (`sys.speed`) powered by `MSHookFunction`.

---

## HexLang 2.0 Documentation & Syntax

### 1. Variables, Conditionals & Loops
```hexlang
# Variables & math
let base = 500
let reward = base * 20

# Conditionals (supports ==, !=, <, >, <=, >=)
if reward > 5000 {
    print "Applying bonus: " + reward
}

# Synchronous loop
repeat 3 {
    print "Tick!"
}
```

### 2. Mach-VM Memory Scanner (`int32` & `float32`)
Scans readable/writable virtual memory regions (`VM_PROT_READ | VM_PROT_WRITE`) of the host process.

| Command | Description | Example |
| :--- | :--- | :--- |
| `mem.scan <int>` | Initial `int32` memory scan | `mem.scan 500` |
| `mem.filter <int>` | Narrow down cached addresses after value changes in-game | `mem.filter 450` |
| `mem.write <int>` | Overwrite all matched addresses with a new `int32` value | `mem.write 999999` |
| `mem.scan_float <float>` | Initial `float32` memory scan (coordinates, timers, speed) | `mem.scan_float 1.5` |
| `mem.filter_float <float>` | Filter cached `float32` addresses | `mem.filter_float 2.0` |
| `mem.write_float <float>` | Overwrite matched addresses with a `float32` value | `mem.write_float 5.0` |
| `mem.list` | Dump the first 12 matched hex addresses (`0x...`) to console | `mem.list` |
| `mem.freeze <val>` | Continuously lock matched addresses every `0.2s` | `mem.freeze 999999` |
| `mem.unfreeze` | Release active memory freeze | `mem.unfreeze` |

### 3. Objective-C Runtime Inspector & Swizzler
Inspects loaded classes and dynamically replaces method implementations (`IMP`) at runtime without restarting the app.

| Command | Description | Example |
| :--- | :--- | :--- |
| `objc.find "<query>"` | Search loaded classes matching substring | `objc.find "Store"` |
| `objc.methods "<Class>"` | List instance methods of a target class | `objc.methods "StoreManager"` |
| `objc.hook "<Class.method>" -> <val>` | Hook method to return `true`, `false`, or an integer | `objc.hook "StoreManager.isPro" -> true` |

### 4. Speedhack, Timers & System Controls

| Command | Description | Example |
| :--- | :--- | :--- |
| `sys.speed <scale>` | Dilate (`0.4` slow-mo) or accelerate (`3.0` fast-forward) game time | `sys.speed 0.4` |
| `sys.info` | Display target Bundle ID, PID, current speed, and cached address count | `sys.info` |
| `every <sec> { ... }` | Run a background block every `N` seconds | `every 1.0 { mem.write 999 }` |
| `stop` | Stop all active `every` timers, memory freezes, and reset speed to `1.0x` | `stop` |
| `help` | Print built-in command cheat sheet inside the console | `help` |

---

## Practical Tutorials

### Tutorial 1: Patching In-Game Currency (Int32)
1. Open your target game and note your current coin balance (e.g. `120`).
2. Tap the floating **`</>`** button and run:
   ```hexlang
   mem.scan 120
   ```
3. Spend or earn some coins so the balance changes (e.g. to `95`), then filter:
   ```hexlang
   mem.filter 95
   ```
4. Once `1–10` addresses remain, overwrite or freeze them:
   ```hexlang
   mem.write 999999
   ```

### Tutorial 2: Unlocking Pro / VIP Features Live
1. Search for relevant manager classes:
   ```hexlang
   objc.find "Premium"
   ```
2. Inspect methods of the discovered class:
   ```hexlang
   objc.methods "PremiumManager"
   ```
3. Swizzle the check method on the fly:
   ```hexlang
   objc.hook "PremiumManager.hasUnlockedVIP" -> true
   ```

### Tutorial 3: Saving & Auto-Running Scripts
- Place any script at `/var/mobile/Documents/script.hex` and tap **`LOAD`** in the console to load it into the editor.
- To run a script automatically every time a game launches, save it as `/var/mobile/Documents/autorun.hex` and enable **Auto-Run autorun.hex on Launch** in **Settings -> RuntimeX**.

---

## Installation

1. Download the compiled `RuntimeX-deb` artifact from the **Actions** tab (or build from source using **Theos**).
2. Transfer the `.deb` package to your device and install it via **Filza** (requires `mobilesubstrate` and `preferenceloader`).
3. **Respring** your device and configure themes, language, and filters under **Settings -> RuntimeX**.

---

## Author

Developed by **binarycrypted** — built for low-level iOS runtime research and reverse engineering.
