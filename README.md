# GodotCAD-Godot-AutoCAD-like
GodotCAD 📐

A godot-based AutoCAD-like 2D drafting tool. Draw, edit, and save technical drawings. Written in GDScript, fully open-source.

[![Godot 4](https://img.shields.io/badge/Godot-4.x-478CBF?style=for-the-badge&logo=godot-engine)](https://godotengine.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)

---

🎯 Goals
GodotCAD aims to provide a lightweight, modular, and functional 2D CAD tool for:

    Drawing technical plans
    Editing geometries
    Exporting to DXF format (industry standard)
    Supporting engineering modules (e.g., static beam calculation)


---

⚠️ About Development: "Vibecoding" 🤖
Full transparency: This project was entirely developed using Vibecoding (100% AI-assisted development).
→ What this means:

    The code may not be optimized.
    Some solutions might seem "hacky".
    OOP/Godot best practices may not always be followed.


Your help is welcome! If you are a developer and want to:

    Refactor the code
    Optimize performance
    Add new features

→ Feel free to open a Pull Request or an Issue!

---

✨ Current Features
Geometry

    Draw lines, circles, and arcs


Snapping (SnapManager)

    Endpoint, midpoint, center, intersection, perpendicular


Editing Tools (SelectionManager)

    Move, copy, rotate, scale
    Mirror (with/without source deletion)
    Offset (visual mode or distance input, with parallel polyline calculation)
    Trim


Selection

    Click, selection box (window/crossing), control points (Grips)


Export

    DXF R12 (AC1009) format


Layers

    Layer management


---

🛠️ Tech Stack

    Engine: Godot 4.x
    Language: GDScript
