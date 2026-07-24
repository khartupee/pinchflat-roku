# Unified Workspace Context: Pinchflat + Roku Client

## 1. Project Architecture Overview
This workspace (`pinchflat-workspace`) manages two co-dependent repositories that form a full-stack media management and streaming ecosystem:

- **`pinchflat-server/`** (stored in `pinchflat-roku/`): The backend Phoenix/Elixir server running Pinchflat. Handles media indexing, YouTube downloads via yt-dlp, local media file storage, and exposes REST API endpoints on port `8945`.
- **`roku-client/`** (stored in `pinchflat-roku-client/`): The frontend Roku TV client built using BrightScript and Roku SceneGraph (RSG). Provides a custom TV channel interface for browsing, streaming, and managing content hosted by the Pinchflat server.

```
                  ┌──────────────────────────────────┐
                  │        pinchflat-workspace       │
                  └─────────────────┬────────────────┘
                                    │
           ┌────────────────────────┴────────────────────────┐
           ▼                                                 ▼
┌──────────────────────┐                         ┌──────────────────────┐
│   pinchflat-server   │                         │     roku-client      │
│  (Docker / REST API) │ ◄─── HTTP / REST API ──► │ (BrightScript / RSG) │
│   [pinchflat-roku]   │                         │[pinchflat-roku-client]
└──────────────────────┘                         └──────────────────────┘
```

---

## 2. Sub-Repository Details

### A. Backend: `pinchflat-roku/`
* **Primary Role:** Video indexing, downloads via yt-dlp, local file storage, and REST API backend.
* **Environment:** Docker container managed via Docker Compose (`compose.yaml`).
* **Default Port:** `8945` (HTTP).
* **Key Responsibilities:**
  * Serving media library metadata endpoints and thumbnail image assets.
  * Streaming local video files directly to client devices over HTTP with byte-range support.
  * Processing administrative actions (e.g., deleting local media files, registering ignore rules for feeds or individual videos).

### B. Frontend: `roku-client/` (stored in `pinchflat-roku-client/`)
* **Primary Role:** Native Roku channel UI for media consumption and library management on TV.
* **Tech Stack:** BrightScript, Roku SceneGraph (RSG).
* **Key Components:**
  * **Main Grid / Poster List:** Renders available Pinchflat media items visually.
  * **Video Player Node (`Video`):** Handles video stream playback given direct media URLs. Supports play, stop, and standard remote controls (such as back-button intercepts).
  * **Admin Actions Screen:** UI controls (accessible via the Options `*` button) for triggering media deletion directly from the TV remote.
* **Registry & Persistent Settings:**
  * Uses `roRegistrySection` with section name `"AppSettings"`.
  * **`serverURL`**: String representing the custom server IP and port (e.g., `192.168.1.7:8945`).
  * **`showPostPlayDialog`**: Boolean ("true"/"false") indicating whether to show a confirmation dialog when a video finishes playing.
* **Networking & Data Flow:**
  * Uses `roUrlTransfer` inside asynchronous SceneGraph `Task` nodes (`APITask`) for non-blocking HTTP API calls.
  * Dynamic server target URL is configured globally.

---

## 3. API & Communication Contract

### Base URL Structure
`http://<SERVER_IP>:8945/` (Rewritten dynamically in the client via the custom `serverURL` registry setting).

### Primary Endpoints Table
| Intent | HTTP Method | Endpoint | Example Request | Expected Response |
| :--- | :--- | :--- | :--- | :--- |
| **Get Downloaded Videos** | `GET` | `/api/v1/videos` | `http://<IP>:8945/api/v1/videos` | JSON array of downloaded video objects |
| **Stream Video (Range-supported)** | `GET` | `/media/:uuid/stream` | `http://<IP>:8945/media/<uuid>/stream` | Video stream (supports seeking/rewinding) |
| **Get Video Thumbnail** | `GET` | `/media/:uuid/episode_image.<ext>` | `http://<IP>:8945/media/<uuid>/episode_image.jpg` | Returns separate `.jpg` if present on disk; otherwise extracts embedded cover art on-the-fly from the `.mp4` using `ffmpeg`. |
| **Delete Media** | `DELETE` | `/api/v1/videos/:id` | `DELETE http://<IP>:8945/api/v1/videos/:id` | `204 No Content` (deletes both DB record and physical files on disk) |
| **Ignore Media** | `POST` | `/api/v1/videos/:id/ignore` | `POST http://<IP>:8945/api/v1/videos/:id/ignore` | Registers an ignore/exclusion rule for a video on the server |

---

## 4. Multi-Repo Rules for AI Agents (Zed Assistant)

When generating, refactoring, or inspecting code across this workspace, strictly observe the following rules:

1. **JSON API as Source of Truth:**
   * The Roku client relies **entirely on the JSON REST API** (`/api/v1/videos`) to populate its listings.
   * **Do not use RSS feeds** on the client to fetch media lists, as RSS feeds are source-specific and bypass database ID mapping needed for client-side administration (like deleting files).
2. **On-the-Fly Image Fallbacks:**
   * If a video doesn't have a separate thumbnail file, the server (`episode_image` action in `PodcastController`) extracts the embedded `attached_pic` (MJPEG) stream from the `.mp4` on-the-fly. Do not fall back to capturing arbitrary frames (e.g. at 2 seconds), as this results in repetitive talking-head frames for news/vlog sources. If extraction fails, return a clean `404` so the client can show its default placeholder.
3. **Additive Design & Standard Web UI Preservation:**
   * **All backend changes must be strictly additive.** The standard browser-based Pinchflat web interface, its controllers (`PinchflatWeb.MediaItems.MediaItemController`), and standard LiveView actions **must never be modified or broken**.
   * API endpoints for Roku or other clients must remain strictly scoped inside isolated controllers under `/api/v1` to prevent any side effects or redirections affecting browser users.
4. **BrightScript Concurrency & Safe Event Parameters:**
   * Never issue synchronous `roUrlTransfer` network calls on the main Render / UI thread. All network operations must run inside an asynchronous `Task` node.
   * Every `Task` node implementation **must** include an `init()` function configuring its entry-point, for example: `m.top.functionName = "run"`. Without this, setting `control = "RUN"` on the task does nothing.
   * **Do not read thread-updated fields dynamically in callbacks.** Observers on the Main or Task thread (such as `onThumbnailLoaded` or `onActionRequest`) must accept the `event` parameter and extract data safely with `event.GetData()`. This prevents multi-threaded overwrites and race conditions.
5. **Dynamic Deployment Paths:**
   * Deployment scripts (`deploy.sh` and `deployultra.sh`) dynamically resolve their path using `PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"`. This ensures they always target your active workspace (`pinchflat-workspace/pinchflat-roku-client`) regardless of how they are invoked.
