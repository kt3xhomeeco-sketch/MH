/* UI-thread mouse filter: only the visible assembly tree rectangle. No keys. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
typedef struct { int kind, x, y; } Event;
static HHOOK hook;
static HWND main_window, view_window;
static RECT region;
static Event events[128];
static unsigned head, tail;
static int held;
static double matched_scale=1.0;
static BOOL CALLBACK find_main(HWND window, LPARAM value) {
  WCHAR title[256]; RECT rect;
  if (!IsWindowVisible(window) || GetWindow(window,GW_OWNER)) return TRUE;
  GetWindowTextW(window,title,256);
  if (!wcsstr(title,L"SketchUp")) return TRUE;
  GetClientRect(window,&rect);
  LONG area=rect.right*rect.bottom;
  if (area>*(LONG*)value) { main_window=window; *(LONG*)value=area; }
  return TRUE;
}
typedef struct { int w,h,best,proportional; double scale; } Search;
static BOOL CALLBACK find_view(HWND window, LPARAM value) {
  Search *s=(Search*)value; RECT rect;
  if (!IsWindowVisible(window)) return TRUE;
  GetClientRect(window,&rect);
  int score=abs(rect.right-s->w)+abs(rect.bottom-s->h);
  double scale=1.0;
  if (s->proportional) {
    scale=(double)rect.right/s->w;
    if (scale<0.5 || scale>8.0) return TRUE;
    score=abs(rect.bottom-(int)(s->h*scale+0.5));
  }
  if (score<s->best) { s->best=score; s->scale=scale; view_window=window; }
  return TRUE;
}
static LRESULT CALLBACK filter(int code, WPARAM remove, LPARAM address) {
  if (code>=0 && remove==PM_REMOVE) {
    MSG *msg=(MSG*)address;
    POINT p=msg->pt;
    if (msg->message==WM_MOUSEWHEEL) { p.x=GET_X_LPARAM(msg->lParam); p.y=GET_Y_LPARAM(msg->lParam); }
    if (GetAncestor(msg->hwnd,GA_ROOT)==main_window ||
        (msg->message==WM_MOUSEWHEEL && GetAncestor(WindowFromPoint(p),GA_ROOT)==main_window)) {
      ScreenToClient(view_window,&p);
      int kind=0;
      if (msg->message==WM_LBUTTONDOWN && !PtInRect(&region,p)) held=0;
      if ((msg->message==WM_LBUTTONDOWN || msg->message==WM_LBUTTONDBLCLK) && PtInRect(&region,p)) { kind=1; held=1; }
      if (msg->message==WM_MOUSEWHEEL && PtInRect(&region,p)) kind=GET_WHEEL_DELTA_WPARAM(msg->wParam)>0 ? 2 : 3;
      int release=msg->message==WM_LBUTTONUP && held;
      if (kind || release) {
        if (kind) {
          unsigned next=(head+1)%128;
          if (next!=tail) { events[head]=(Event){kind,p.x,p.y}; head=next; }
        }
        if (release) held=0;
        msg->message=WM_NULL; msg->wParam=msg->lParam=0;
      }
    }
  }
  return CallNextHookEx(hook,code,remove,address);
}
__declspec(dllexport) void AHStop(void) {
  if (hook) UnhookWindowsHookEx(hook);
  hook=NULL; main_window=view_window=NULL; head=tail=0; held=0; SetRectEmpty(&region);
}
__declspec(dllexport) int AHStart(int width,int height) {
  AHStop(); LONG area=0; Search s={width,height,1000000,0,1.0};
  if (width<=0 || height<=0) return 0;
  EnumThreadWindows(GetCurrentThreadId(),find_main,(LPARAM)&area);
  if (!main_window) return 0;
  EnumChildWindows(main_window,find_view,(LPARAM)&s);
  if (!view_window || s.best>12) {
    s.best=1000000; s.proportional=1; view_window=NULL;
    EnumChildWindows(main_window,find_view,(LPARAM)&s);
  }
  if (!view_window || s.best>12) return 0;
  matched_scale=s.scale;
  hook=SetWindowsHookExW(WH_GETMESSAGE,filter,NULL,GetCurrentThreadId());
  return hook!=NULL;
}
__declspec(dllexport) void AHRect(int left,int top,int right,int bottom) { SetRect(&region,left,top,right,bottom); }
__declspec(dllexport) int AHPoll(int *kind,int *x,int *y) {
  if (head==tail) return 0;
  *kind=events[tail].kind; *x=events[tail].x; *y=events[tail].y; tail=(tail+1)%128; return 1;
}
__declspec(dllexport) int AHViewport(int *left,int *top,int *right,int *bottom) {
  RECT rect; POINT p={0,0};
  if (!view_window || !IsWindow(view_window)) return 0;
  GetClientRect(view_window,&rect); ClientToScreen(view_window,&p);
  *left=p.x; *top=p.y; *right=p.x+rect.right; *bottom=p.y+rect.bottom; return 1;
}
__declspec(dllexport) int AHActive(void) { return hook!=NULL; }
__declspec(dllexport) double AHScale(void) { return matched_scale; }
