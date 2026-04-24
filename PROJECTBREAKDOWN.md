# 📖 Storybook Reader App (Flutter) — Project Plan

## 🎯 Goal

Build a tablet-based storybook reader app where:

- Parents can read books to kids
- Books are displayed as swipeable pages
- Cartoon characters (based on real family photos) appear on screen
- Characters animate and interact during reading (page turns, idle animations, etc.)
- App is simple, offline, and kid-friendly

---

## 🧠 Core Concept

A custom e-reader + animated overlay system

Instead of complex EPUB rendering:
- Books are stored as image-based pages
- Characters are rendered as overlay widgets
- Animations are triggered by user interaction (swipes, taps)

---

## 🧱 Tech Stack

- Framework: Flutter
- Language: Dart
- Target Platform: Android Tablet
- Dev Environment: Windows + Android Emulator
- Optional Later: Raspberry Pi (Flutter Linux build)

---

## 📦 MVP Features (Version 1)

### 📚 Reader
- Load book from local assets
- Display one page at a time (image-based)
- Swipe left/right for navigation
- Maintain current page state

### 🧍 Characters
- 1–2 characters displayed in screen corners
- Basic animation states:
  - idle (blink / bounce)
  - pageTurnAssist
- Trigger animation on page swipe

### 🗂 Library
- Simple book selection screen
- Load predefined books

### ⚙️ Settings (Hidden Parent Mode)
- Toggle characters on/off
- Import new books
- Import character packs

---

## 📁 Project Structure

```
lib/
  main.dart
  app.dart

  models/
    book.dart
    character.dart
    page_asset.dart

  screens/
    home_screen.dart
    reader_screen.dart
    library_screen.dart
    settings_screen.dart
    admin_screen.dart

  widgets/
    book_page_view.dart
    character_overlay.dart
    reader_controls.dart

  services/
    book_service.dart
    character_service.dart
    storage_service.dart

  animations/
    character_animator.dart

assets/
  books/
  characters/
  ui/
```

---

## 📖 Book Format

Books are stored as image sequences:

```
assets/books/book_1/
  manifest.json
  page_001.png
  page_002.png
```

### Example manifest:

```json
{
  "title": "My First Book",
  "pages": 10
}
```

---

## 🧍 Character Format

Characters are image-based animation sets:

```
assets/characters/grandma/
  manifest.json
  idle_1.png
  idle_2.png
  turn_1.png
  turn_2.png
```

### Example manifest:

```json
{
  "name": "Grandma",
  "states": ["idle", "pageTurnAssist"]
}
```

---

## 🎞 Animation System (Simple)

State-driven animation:

- idle → looping frames
- pageTurnAssist → triggered on swipe

Example logic:

```
onPageSwipe():
  character.setState("pageTurnAssist")
  delay(1s)
  character.setState("idle")
```

---

## 🎮 UI Flow

1. Home Screen  
2. Library Screen  
3. Reader Screen  
   - Page display  
   - Character overlay  
   - Swipe navigation  

---

## 🚀 Development Phases

### Phase 1 — Basic Reader
- Build page viewer
- Implement swipe navigation
- Load static image book

### Phase 2 — Character Overlay
- Add character widget
- Implement idle animation
- Trigger animation on page turn

### Phase 3 — Asset System
- Load books from folder
- Load characters from folder
- Basic manifest parsing

### Phase 4 — Polish
- Fullscreen mode
- Orientation lock (landscape)
- Hide system UI
- Simple parent settings

---

## 🤖 AI Integration (Later)

### Character Creation
- Convert family photos → cartoon style
- Generate consistent poses
- Export PNG frames

### Optional Enhancements
- Voice narration
- Character reactions to reading progress
- Speech bubbles

---

## ⚠️ Out of Scope (for MVP)

- EPUB parsing
- Online syncing
- Cloud storage
- Complex animation rigs
- Real-time AI inference

---

## 🧪 Dev Commands

```
flutter run
flutter devices
flutter emulators
```

---

## 🏁 First Milestone

Display a book page and animate a character when swiping.

---

## 💡 Future Ideas

- Multiple characters on screen
- Voice + lip sync
- Interactive elements for kids
- “Read with Grandma” mode (recorded narration)
- Character personalities

---

## 🧠 Key Design Principle

Keep everything simple, offline, and delightful.

This is a gift, not a platform.

---

## ✅ Success Criteria

- Smooth page swiping
- Characters feel alive
- Easy for non-technical users
- Runs cleanly on tablet offline