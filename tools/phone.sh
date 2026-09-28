# source tools/phone.sh — управление телефоном через adb: shot NAME, ui, tapd ТЕКСТ, logs. Перед нажатием по координатам — wake: на зарядке включается заставка.
export MSYS_NO_PATHCONV=1
export PATH="/d/APP/tools/sdk/platform-tools:$PATH"
D=64071JEA314114
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.shots"; mkdir -p "$S"
a() { adb -s $D "$@"; }
wake() { a shell input keyevent KEYCODE_WAKEUP; }
shot() { wake; a exec-out screencap -p > "$S/$1.png"; echo "$S/$1.png"; }
dump() { a shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; a shell cat /sdcard/ui.xml; }
# list: label | bounds
ui() { wake; dump | python -c "
import sys,re,html
x=sys.stdin.read()
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    d=re.search(r'content-desc=\"([^\"]*)\"',n).group(1); t=re.search(r' text=\"([^\"]*)\"',n).group(1)
    b=re.search(r'bounds=\"([^\"]*)\"',n).group(1)
    lab=html.unescape(d or t).replace('\n',' / ')
    if lab: print(lab,'|',b)
"; }
# tap the first element whose label contains $1
tapd() { wake; local b; b=$(dump | python -c "
import sys,re,html
x=sys.stdin.read(); q=sys.argv[1].lower()
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    d=re.search(r'content-desc=\"([^\"]*)\"',n).group(1); t=re.search(r' text=\"([^\"]*)\"',n).group(1)
    if q in html.unescape(d or t).lower():
        b=[int(v) for v in re.findall(r'\d+',re.search(r'bounds=\"([^\"]*)\"',n).group(1))]
        print((b[0]+b[2])//2,(b[1]+b[3])//2); break
" "$1"); if [ -z "$b" ]; then echo "not found: $1"; return 1; fi; a shell input tap $b; echo "tapped $1 at $b"; }
logs() { a logcat -d -v time -t "${1:-300}" | grep -iE "flutter|homeplay|mpv|media_kit|AndroidRuntime|FATAL" | grep -v viewport; }
