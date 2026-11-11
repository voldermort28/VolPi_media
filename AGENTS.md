# VolPi Media - Developer & Agent Guidelines

## ⚠️ BẮT BUỘC: QUY TẮC NÂNG PHIÊN BẢN (VERSION BUMP RULE)

MỖI KHI thực hiện chỉnh sửa code, thêm tính năng, sửa bug liên quan đến App TV (`app-tv/`) hoặc chuẩn bị build/push release mới:
**BẠN BẮT BUỘC PHẢI LUÔN LUÔN TĂNG SỐ PHIÊN BẢN (Version & Build Number). KHÔNG ĐƯỢC QUÊN BƯỚC NÀY!**

### 3 File BẮT BUỘC phải đồng bộ số phiên bản:

1. **`app-tv/pubspec.yaml`**:
   - Tăng `version: X.Y.Z+BUILD` (ví dụ: `2.2.17+83` -> `2.2.18+84`).
   - `X.Y.Z` là phiên bản hiển thị, `BUILD` là số nguyên tăng dần phục vụ OTA cập nhật.

2. **`version.json`**:
   - `version`: `"X.Y.Z"`
   - `build`: `BUILD` (số nguyên)
   - `tag_name`: `"vX.Y.Z"`
   - `changelog`: Ghi chú ngắn gọn, súc tích các điểm mới hoặc lỗi vừa sửa trong bản cập nhật.
   - `published_at`: Thời điểm cập nhật theo định dạng ISO 8601.

3. **`public/download/version.json`**:
   - Giữ nguyên nội dung đồng bộ 100% với `version.json`.

---

## 🚀 Quy Trình Build & Triển Khai (Deployment Workflow)

1. **Đồng bộ phiên bản**: Tăng version ở cả 3 file trên trước khi commit.
2. **Git Commit & Push**:
   - Commit với format: `feat: ... (vX.Y.Z+BUILD)` hoặc `fix: ... (vX.Y.Z+BUILD)`.
   - Push lên nhánh `main` (`origin main`).
   - GitHub Actions sẽ tự động trigger workflow `Build VolPi Media APK & IPA` để build Android APK, iOS IPA và macOS Zip.
3. **Triển khai VPS (`stremio.laboon.vn`)**:
   - Địa chỉ VPS: `116.118.48.68`, Port SSH: `288`, User: `root`.
   - Thư mục backend: `/www/wwwroot/stremio.laboon.vn`.
   - Sử dụng `scp -P 288` để chép các file backend (`index.js`, `services/`, `scrapers/`, `addons/`, `config.js`, `public/`, `version.json`, `public/download/version.json`).
   - Khởi động lại tiến trình PM2: `pm2 restart stremio-vlxx && pm2 save`.
   - Kiểm tra live: `https://stremio.laboon.vn/api/version`.
