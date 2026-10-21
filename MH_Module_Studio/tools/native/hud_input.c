/* Windows x64, process-local UI-thread message filter. No Ruby callbacks. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef struct { int key, down, repeat; } KeyEvent;
static HHOOK hook;
static HWND main_window;
static KeyEvent events[256];
static unsigned int head, tail;
static double matched_scale=1.0;

static BOOL CALLBACK find_main(HWND hwnd, LPARAM arg) {
  WCHAR title[512]; RECT rect;
  if (!IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER)) return TRUE;
  GetWindowTextW(hwnd, title, 512);
  if (!wcsstr(title, L"SketchUp")) return TRUE;
  GetClientRect(hwnd, &rect);
  if ((rect.right-rect.left)*(rect.bottom-rect.top) > *(LONG *)arg) {
    *(LONG *)arg = (rect.right-rect.left)*(rect.bottom-rect.top);
    main_window = hwnd;
  }
  return TRUE;
}

static int protected_key(WPARAM key) {
  return (key >= 'A' && key <= 'Z') || (key >= '0' && key <= '9') ||
    (key >= VK_NUMPAD0 && key <= VK_NUMPAD9) ||
    key == VK_ESCAPE || key == VK_SPACE || key == VK_BACK || key == VK_TAB ||
    key == VK_RETURN || key == VK_LEFT || key == VK_RIGHT || key == VK_PRIOR || key == VK_NEXT;
}

static LRESULT CALLBACK filter(int code, WPARAM remove, LPARAM address) {
  if (code >= 0 && remove == PM_REMOVE) {
    MSG *message = (MSG *)address;
    int down = message->message == WM_KEYDOWN;
    int up = message->message == WM_KEYUP;
    if ((down || up) && GetAncestor(message->hwnd, GA_ROOT) == main_window &&
        protected_key(message->wParam) && !(GetKeyState(VK_MENU) & 0x8000) &&
        !(GetKeyState(VK_LWIN) & 0x8000) && !(GetKeyState(VK_RWIN) & 0x8000)) {
      unsigned int next = (head + 1) % 256;
      if (next != tail) {
        events[head].key = (int)message->wParam;
        events[head].down = down;
        events[head].repeat = down && (message->lParam & (1LL << 30)) ? 2 : 1;
        head = next;
      }
      message->message = WM_NULL;
      message->wParam = message->lParam = 0;
    }
  }
  return CallNextHookEx(hook, code, remove, address);
}

__declspec(dllexport) void MHRemove(void) {
  if (hook) UnhookWindowsHookEx(hook);
  hook = NULL; main_window = NULL; head = tail = 0;
}

__declspec(dllexport) int MHInstall(void) {
  LONG area = 0;
  if (hook) return 1;
  EnumThreadWindows(GetCurrentThreadId(), find_main, (LPARAM)&area);
  if (!main_window) return 0;
  hook = SetWindowsHookExW(WH_GETMESSAGE, filter, NULL, GetCurrentThreadId());
  return hook != NULL;
}

__declspec(dllexport) int MHPoll(int *key, int *down, int *repeat) {
  if (head == tail) return 0;
  *key = events[tail].key; *down = events[tail].down; *repeat = events[tail].repeat;
  tail = (tail + 1) % 256;
  return 1;
}

typedef struct { int width, height, score, proportional; HWND window; double scale; } ViewSearch;
static BOOL CALLBACK find_view(HWND hwnd, LPARAM arg) {
  ViewSearch *search = (ViewSearch *)arg; RECT rect; int dx, dy, score;
  if (!IsWindowVisible(hwnd)) return TRUE;
  GetClientRect(hwnd, &rect);
  dx = rect.right - search->width; dy = rect.bottom - search->height;
  score = (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy);
  double scale=1.0;
  if (search->proportional) {
    scale=(double)rect.right/search->width;
    if (scale<0.5 || scale>8.0) return TRUE;
    dy=rect.bottom-(int)(search->height*scale+0.5); score=dy<0 ? -dy : dy;
  }
  if (score < search->score) { search->score = score; search->window = hwnd; search->scale=scale; }
  return TRUE;
}

/* x/y are physical view pixels; 'over' excludes covering HtmlDialogs. */
__declspec(dllexport) int MHCursor(int width, int height, int *x, int *y, int *left, int *over) {
  ViewSearch search = {width, height, 1000000, 0, NULL, 1.0}; POINT point; RECT rect; HWND under;
  if (width<=0 || height<=0) return 0;
  if (!main_window || !GetCursorPos(&point)) return 0;
  EnumChildWindows(main_window, find_view, (LPARAM)&search);
  if (!search.window || search.score>12) {
    search.score=1000000; search.proportional=1; search.window=NULL;
    EnumChildWindows(main_window,find_view,(LPARAM)&search);
  }
  if (!search.window || search.score > 12) return 0;
  matched_scale=search.scale;
  under = WindowFromPoint(point);
  *over = GetAncestor(under, GA_ROOT) == main_window;
  ScreenToClient(search.window, &point); GetClientRect(search.window, &rect);
  *over = *over && PtInRect(&rect, point);
  *x = point.x; *y = point.y; *left = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
  return 1;
}

__declspec(dllexport) int MHActive(void) { return hook != NULL; }
__declspec(dllexport) double MHScale(void) { return matched_scale; }
