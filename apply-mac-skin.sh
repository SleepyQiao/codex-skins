#!/usr/bin/env bash
set -euo pipefail
die(){ printf '%s
' "$*" >&2; exit 1; }
architecture_is_compatible(){ local h="$1" a="$2" x; for x in $a; do [[ "$x" == "$h" ]] && return 0; done; return 1; }
json_escape(){
  local v="$1"
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  v=${v//$'\b'/\\b}
  v=${v//$'\f'/\\f}
  v=${v//$'\n'/\\n}
  v=${v//$'\r'/\\r}
  v=${v//$'\t'/\\t}
  printf %s "$v"
}
cdp_request_payload(){ printf '{"id":1,"method":"Runtime.evaluate","params":{"expression":"%s","returnByValue":true}}' "$(json_escape "$1")"; }
if [[ "${CODEX_SKIN_TEST_LIB:-}" == 1 ]];then return 0;fi
usage(){ printf '%s
' 'Usage: ./apply-mac-skin.sh <skin-id> [--app-path PATH] [--port N] [--timeout N]' >&2;exit 2;}
positive(){ [[ "$1" =~ ^[0-9]+$ ]]&&(( $1>0 ))||die "$2 must be a positive integer."; }
exec_for_app(){ local a="$1" n m rm e p;n="$(defaults read "$a/Contents/Info" CFBundleExecutable 2>/dev/null)"||die "Could not read CFBundleExecutable from $a/Contents/Info.plist.";[[ -n "$n" && "$n" != */* && "$n" != *..* ]]||die 'CFBundleExecutable is unsafe.';m="$a/Contents/MacOS";[[ -d "$m" ]]||die "Application bundle is missing Contents/MacOS: $a";rm="$(cd -P "$m"&&pwd)";e="$m/$n";[[ -f "$e" && -x "$e" && ! -L "$e" ]]||die "Application executable is missing, not executable, or a symlink: $e";p="$(cd -P "$(dirname "$e")"&&pwd)";[[ "$p" == "$rm" ]]||die 'Resolved executable escapes Contents/MacOS.';printf '%s
' "$e"; }
close_visible(){ [[ -n "$1" ]]||return 0;if ! osascript - "$1" <<'OSA'
on run argv
 tell application "System Events"
  repeat with p in every application process whose bundle identifier is item 1 of argv
   if visible of p then
    try
     tell p to close every window
    end try
   end if
  end repeat
 end tell
end run
OSA
then printf '%s
' 'Could not close visible windows; close unsaved windows manually. No process was force-terminated.' >&2;fi; }
target_from_json(){ /usr/bin/osascript -l JavaScript -e '
ObjC.import("Foundation");var d=$.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile,a=JSON.parse(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(d,$.NSUTF8StringEncoding)));if(!Array.isArray(a))throw Error("CDP target list is not an array.");var p=a.filter(function(x){return x&&x.type==="page"&&typeof x.webSocketDebuggerUrl==="string";}),t=p.filter(function(x){return x.url==="app://-/index.html";})[0]||(p.length===1?p[0]:null);if(t)$.NSFileHandle.fileHandleWithStandardOutput.writeData($.NSString.stringWithString(t.webSocketDebuggerUrl).dataUsingEncoding($.NSUTF8StringEncoding));'; }
make_expression(){ /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import("Foundation");
function bad(x){throw Error(x)}function text(p,l){var d=$.NSData.dataWithContentsOfFile($(p));if(!d)bad("Missing "+l+": "+p);var s=ObjC.unwrap($.NSString.alloc.initWithDataEncoding(d,$.NSUTF8StringEncoding));if(s===null)bad("Could not decode "+l);return s}function obj(p,l){var v;try{v=JSON.parse(text(p,l))}catch(e){bad(l+" is not valid JSON")}if(!v||Array.isArray(v)||typeof v!=="object")bad(l+" must be a JSON object");return v}function str(v,l){if(typeof v!=="string"||!v.trim())bad(l+" must be nonempty");return v}function file(r,v,l,o){if((v===undefined||v===null)&&o)return null;str(v,l);if(v.indexOf("\\")>=0||v[0]==="/"||v.indexOf(":")>=0||v.split("/").some(function(x){return !x||x==="."||x===".."}))bad(l+" must be a safe relative path");var ru=$.NSURL.fileURLWithPath($(r)).URLByStandardizingPath.URLByResolvingSymlinksInPath,fu=ru.URLByAppendingPathComponent($(v)).URLByStandardizingPath.URLByResolvingSymlinksInPath,rp=ObjC.unwrap(ru.path),fp=ObjC.unwrap(fu.path);if(fp.indexOf(rp+"/")!==0)bad(l+" resolves outside skin package");if(!$.NSFileManager.defaultManager.fileExistsAtPath($(fp)))bad(l+" does not exist");return fp}function mime(p){var e=p.split(".").pop().toLowerCase();return e==="jpg"||e==="jpeg"?"image/jpeg":e==="png"?"image/png":e==="webp"?"image/webp":"application/octet-stream"}function run(a){var r=a[0],s=a[1],m=obj(s+"/skin.json","skin.json");if(m.schemaVersion!==1||m.kind!=="dream")bad("skin.json must declare schemaVersion 1 and kind dream");str(m.id,"skin.json id");str(m.name,"skin.json name");if(typeof m.swatchColor!=="string"||!/^#[0-9a-fA-F]{6}$/.test(m.swatchColor))bad("skin.json swatchColor must be #RRGGBB");var bg=file(s,m.background,"background",false),tp=file(s,m.theme,"theme",false),sp=file(s,m.style,"style",true),t=obj(tp,"theme.json");str(t.id,"theme.json id");if(["system","light","dark"].indexOf(t.appearance)<0)bad("theme.json appearance must be system, light, or dark");var css=text(r+"/dream-skin.css","runtime CSS"),renderer=text(r+"/renderer-inject.js","renderer injection script"),style=sp?text(sp,"style"):"",data=$.NSData.dataWithContentsOfFile($(bg));if(!data)bad("Could not read background");var rep={"__DREAM_SKIN_CSS_JSON__":JSON.stringify(css+"\n"+style),"__DREAM_SKIN_ART_JSON__":JSON.stringify("data:"+mime(bg)+";base64,"+ObjC.unwrap(data.base64EncodedStringWithOptions(0))),"__DREAM_SKIN_THEME_JSON__":JSON.stringify(t),"__DREAM_SKIN_VERSION_JSON__":JSON.stringify("standalone-codex-skin-1"),"__DREAM_SKIN_STYLE_REVISION_JSON__":JSON.stringify("standalone-"+t.id+"-"+style.length)};Object.keys(rep).forEach(function(k){if(renderer.indexOf(k)<0)bad("renderer-inject.js is missing "+k);renderer=renderer.split(k).join(rep[k])});$.NSFileHandle.fileHandleWithStandardOutput.writeData($.NSString.stringWithString(JSON.stringify({name:m.name,expression:renderer})).dataUsingEncoding($.NSUTF8StringEncoding))}
JXA
}
payload_field(){ /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import("Foundation");function run(a){var d=$.NSData.dataWithContentsOfFile($(a[1]));if(!d)throw Error("Could not read renderer payload file");var p=JSON.parse(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(d,$.NSUTF8StringEncoding))),v=p[a[0]];if(typeof v!=="string")throw Error("Invalid renderer payload field");$.NSFileHandle.fileHandleWithStandardOutput.writeData($.NSString.stringWithString(v).dataUsingEncoding($.NSUTF8StringEncoding))}
JXA
}
cdp_eval(){ local q;q="$(cdp_request_payload "$2")";/usr/bin/osascript -l JavaScript - "$1" "$q" <<'JXA'
ObjC.import("Foundation");function bad(x){throw Error(x)}function run(a){var u=$.NSURL.URLWithString($(a[0]));if(!u)bad("Invalid CDP WebSocket URL");var se=$.NSURLSession.sessionWithConfiguration($.NSURLSessionConfiguration.defaultSessionConfiguration),so=se.webSocketTaskWithURL(u),done=false,fail=null;so.resume;so.sendMessageCompletionHandler($.NSURLSessionWebSocketMessage.alloc.initWithString($(a[1])),function(e){if(e){fail="CDP send failed: "+ObjC.unwrap(e.localizedDescription);done=true;return}so.receiveMessageWithCompletionHandler(function(m,e){if(e){fail="CDP receive failed: "+ObjC.unwrap(e.localizedDescription);done=true;return}if(!m){fail="CDP WebSocket closed before replying";done=true;return}var x;try{x=JSON.parse(ObjC.unwrap(m.string))}catch(z){fail="CDP returned invalid JSON";done=true;return}if(x.id!==1)fail="CDP returned unexpected response id";else if(x.error)fail="CDP protocol error: "+JSON.stringify(x.error);else if(!x.result)fail="CDP did not return Runtime.evaluate result";else if(x.result.exceptionDetails)fail="Runtime.evaluate exception: "+JSON.stringify(x.result.exceptionDetails);done=true})});var end=$.NSDate.dateWithTimeIntervalSinceNow(5);while(!done&&$.NSDate.date.compare(end)===-1)$.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(.05));so.cancelWithCloseCodeReason(1000,null);se.invalidateAndCancel;if(!done)bad("CDP WebSocket timed out after 5 seconds");if(fail)bad(fail)}
JXA
}
main(){ local root id app="" port=9222 timeout=20 run skin x bin bid="" host arches expr payload_file skin_name list ws="" deadline;root="$(cd "$(dirname "${BASH_SOURCE[0]}")"&&pwd)";(($#>=1))||usage;id="$1";shift;[[ -n "$id"&&"$id" != */*&&"$id" != *\\*&&"$id" != *..* ]]||die "Skin id must not contain '/', '\\', or '..'.";while(($#));do case "$1" in --app-path)(($#>=2))||usage;app="$2";shift 2;;--port)(($#>=2))||usage;port="$2";shift 2;;--timeout)(($#>=2))||usage;timeout="$2";shift 2;;*)die "Unknown option: $1";;esac;done;positive "$port" Port;(($port<=65535))||die 'Port must be between 1 and 65535.';positive "$timeout" Timeout;run="$root/runtime";skin="$root/skins/$id";for x in "$run/dream-skin.css" "$run/renderer-inject.js" "$skin/skin.json" "$skin/theme.json" "$skin/background.jpg";do [[ -f "$x" ]]||die "Required skin asset is missing: $x";done;payload_file="$(mktemp "${TMPDIR:-/tmp}/codex-skin-payload.XXXXXX")"||die 'Could not create renderer payload file.';trap 'rm -f "$payload_file"' EXIT;make_expression "$run" "$skin" > "$payload_file"||die 'Skin validation failed. Correct the skin package and retry.';expr="$(payload_field expression "$payload_file")"||die 'Could not read renderer expression.';skin_name="$(payload_field name "$payload_file")"||die 'Could not read skin name.';if [[ -n "$app" ]];then [[ -d "$app" ]]||die "The --app-path bundle does not exist: $app";else for x in /Applications/Codex.app "$HOME/Applications/Codex.app" /Applications/ChatGPT.app "$HOME/Applications/ChatGPT.app";do [[ -d "$x" ]]&&{ app="$x";break;};done;[[ -n "$app" ]]||die 'No Codex or ChatGPT bundle was found. Provide --app-path /path/to/Codex.app.';fi;bin="$(exec_for_app "$app")";bid="$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null||true)";host="$(uname -m)";[[ "$host" == arm64||"$host" == x86_64 ]]||die "Unsupported host architecture '$host'; arm64 and x86_64 only.";arches="$(lipo -archs "$bin" 2>/dev/null)"||die "Could not inspect application architectures with lipo: $bin";if ! architecture_is_compatible "$host" "$arches";then if [[ "$host" == arm64 ]]&&architecture_is_compatible x86_64 "$arches";then /usr/sbin/sysctl -in sysctl.proc_translated >/dev/null 2>&1 || /usr/bin/pgrep -x oahd >/dev/null 2>&1 || die 'This Intel-only app requires Rosetta. Install it with: softwareupdate --install-rosetta --agree-to-license';else die "Application architectures '$arches' are incompatible with host '$host'. Choose a Universal or matching app bundle.";fi;fi;close_visible "$bid";open -n "$app" --args "--remote-debugging-port=$port";deadline=$((SECONDS+timeout));while((SECONDS<deadline));do if list="$(curl --fail --silent --show-error --max-time 2 "http://127.0.0.1:$port/json/list" 2>/dev/null)";then ws="$(printf %s "$list"|target_from_json 2>/dev/null||true)";[[ -n "$ws" ]]&&break;fi;sleep 1;done;[[ -n "$ws" ]]||die "CDP did not expose a usable page at http://127.0.0.1:$port/json/list within $timeout seconds.";cdp_eval "$ws" "$expr"||die 'CDP injection failed. Ensure the app supports remote debugging and retry.';printf 'Applied skin: %s
' "$skin_name";}
main "$@"
