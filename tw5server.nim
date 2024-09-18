import
  asynchttpserver,
  asyncdispatch,
  os,
  strutils,
  times,
  parseopt,
  sequtils,
  algorithm,
  sets,
  uri,
  zippy,
  mimetypes

import strformat
import tables, strtabs
from httpcore import HttpMethod, HttpHeaders

from parseBody import parseMPFD

import json

const
  name = "TW5 server"
  version = "1.3.0"
  style = staticRead("style.css")
  temp = staticRead("template.html")
  js = staticRead("main.js")

const usage = fmt"""
{name} {version}

Usage:
tw5server -a:localhost -p:8000 -d:dir -b:backup

-h this help
-c config file, json format, default tw5server.json
-a address, defautl "127.0.0.1"
-p port, default 8000
-d directory to serve, default `current dir`
-b backup directory, default `backup` in serve dir. `backup/` or `backup\\` for a backup path.
-l show log message
-m max size of uploaded file (MB), default 100

Backups auto-clean strategy:
Keep all backups in current month, keep only the newest one for previous months.
"""

proc time_now(): string =
  return now().format("yyyyMMddHHmmss")

type
  NimHttpResponse = tuple[
    code: HttpCode,
    content: string,
    headers: HttpHeaders
    ]

  NimHttpSettings = object
    directory: string
    mimes: MimeDb
    port: Port
    title: string
    address: string
    name: string
    version: string

# TODO: update web page after upload
proc h_page(settings:NimHttpSettings, content, title, subtitle: string): string =
  var footer = """<div id="footer">$1 v$2</div>""" % [settings.name, settings.version]
  result = temp % [title, style, subtitle, content, footer, js]

proc relativePath(path, cwd: string): string =
  var path2 = path
  var wd = cwd
  if wd.endsWith("/"):
    wd.removeSuffix("/")
  if wd == "/":
    return wd
  elif wd == path2:
    return "/"
  else:
    path2.removePrefix(wd)
  var relpath = path2.replace("\\", "/")
  if (not relpath.endsWith("/")) and (not path.fileExists):
    relpath = relpath&"/"
  if not relpath.startsWith("/"):
    relpath = "/"&relpath
  return relpath

proc relativeParent(path, cwd: string): string =
  var relparent = path.parentDir.relativePath(cwd)
  if relparent == "":
    return "/"
  else:
    return relparent


proc sendNotFound(settings: NimHttpSettings, path: string): NimHttpResponse =
  var content = "<p>The page you requested cannot be found.<p>"
  return (code: Http404, content: h_page(settings, content, $int(Http404), "Not Found"), headers: {"Content-Type": "text/html"}.newHttpHeaders())


proc sendStaticFile(settings: NimHttpSettings, path: string): NimHttpResponse =
  let mimes = settings.mimes
  var ext = path.splitFile.ext
  if ext == "":
    ext = ".txt"
  ext = ext[1 .. ^1]
  let mimetype = mimes.getMimetype(ext.toLowerAscii)
  var file = path.readFile
  return (code: Http200, content: file, headers: {"Content-Type": mimetype}.newHttpHeaders)


proc sendDirContents(settings: NimHttpSettings, dir: string): NimHttpResponse =
  let cwd = settings.directory.absolutePath
  var res: NimHttpResponse
  var files = newSeq[string](0)
  var path = dir.absolutePath
  if not path.startsWith(cwd):
    path = cwd
  if path != cwd and path != cwd&"/" and path != cwd&"\\":
    files.add """<li class="i-back entypo"><a href="$1">..</a></li>""" % [path.relativeParent(cwd)]
  var title = settings.title
  let subtitle = path.relativePath(cwd)
  for i in walkDir(path):
    let name = i.path.extractFilename
    let relpath = i.path.relativePath(path).strip(chars = {'/'}, trailing = false)
    if name == "index.html" or name == "index.htm":
      return sendStaticFile(settings, i.path)
    if i.path.dirExists:
      files.add """<li class="i-folder entypo"><a href="$1">$2</a></li>""" % [relpath, name]
    else:
      files.add """<li class="i-file entypo"><a href="$1">$2</a></li>""" % [relpath, name]
  let ul = """
<ul>
  $1
</ul>
""" % [files.join("\n")]
  res = (code: Http200, content: h_page(settings, ul, title, subtitle), headers: {"Content-Type": "text/html"}.newHttpHeaders())
  return res

proc sendOptions(): NimHttpResponse =
  var header = {"status": "ok", "dav": "tw5/put", "allow": "GET,HEAD,POST,OPTIONS,CONNECT,PUT,DAV,dav", "x-api-access-type": "file"}
  return (code: Http200, content: "", headers: header.newHttpHeaders())

proc logmsg(msg: string, log: bool) =
  if log:
    echo msg

proc getPut(req: Request, path, backup: string, log: bool): NimHttpResponse =
  let content = req.body
  writeFile(path, content)
  logmsg("Update: " & path, log)

  let (dir, name, _) = splitFile(path)
  let backup_name = backup / name & "-" & time_now() & ".html.gz"

  let compressed = compress(content, BestCompression)
  writeFile(backup_name, compressed)
  logmsg("Backup to: " & backup_name, log)

  return (code: Http200, content: "saved", headers: {"Content-Type": "text;charset=UTF-8"}.newHttpHeaders())

proc savePost(req: Request, path, url_path: string, log: bool): NimHttpResponse =
  let
    header = req.headers
    contentType = header.getOrDefault("Content-Type")
    body = parseMPFD(contentType, req.body)
    file = body["file"]
    filename = file.fields["filename"]
    file_body = file.body
    overwrite = body.getOrDefault("overwrite").body

  var
    rsp_content = ""
    code = Http400

  if fileExists(path / filename) and "yes" != overwrite:
    let
      (_, base, ext) = filename.splitFile()
      newName = base & "-" & time_now() & ext

    writeFile(path / newName, file_body)
    let
      rsp_msg = "Save file to " & newName
      msg = rsp_msg & " in " & path
    rsp_content = newName
    code = Http200
    logmsg(msg, log)
  else:
    writeFile(path / filename, file_body)
    let
      rsp_msg = "Save file to " & filename
      msg = rsp_msg & " in " & path
    rsp_content = filename
    code = Http200
    logmsg(msg, log)
  return (code: code, content: rsp_content, headers: {"status": "ok"}.newHttpHeaders())

proc serve(settings: NimHttpSettings, backup: string, log: bool, maxbody: int) =
  var server = newAsyncHttpServer(maxBody = maxbody)
  proc handleHttpRequest(req: Request): Future[void] {.async.} =
    let
      url_path = req.url.path.replace("%20", " ").decodeUrl()
      path = settings.directory / url_path
    var res: NimHttpResponse
    case req.reqMethod:
      of HttpGet:
        if path.dirExists:
          res = sendDirContents(settings, path)
        elif path.fileExists:
          res = sendStaticFile(settings, path)
        else:
          res = sendNotFound(settings, path)
      of HttpPut:
        res = getPut(req, path, backup, log)
      of HttpOptions:
        res = sendOptions()
      of HttpHead:
        res = sendOptions()
      of HttpPost:
        res = savePost(req, path, url_path, log)
      else:
        echo(req.reqMethod)
    await req.respond(res.code, res.content, res.headers)
  asyncCheck server.serve(settings.port, handleHttpRequest, settings.address)

proc currentMonth(ymd: string): string =
  # 20230123 -> 202301
  return ymd[0..<6]

proc old_backups(path, name: string): seq[string] =
  let
    now = time_now()
    c_year_month = currentMonth(now)

    backup_name = path / name
    all_backup_unsort = toSeq(walkPattern(backup_name & "*.html.gz"))
    all_backup = sorted(all_backup_unsort, Descending)

  var
    to_be_removed: seq[string]
    saved_y_m = ""

  for i in all_backup:
    let
      date = i[^22..^1]
      y_m = currentMonth(date)

    if y_m >= c_year_month:
      continue

    if saved_y_m == y_m:
      to_be_removed.add(i)
    else:
      saved_y_m = y_m

  return to_be_removed

proc backupFileName(name: string): string =
  # backup name: name-timestamp.html.gz, e.g, test-20230227142037.html.gz
  return name[0..^21]

proc clean_backup(backup: string): int =
  var names: HashSet[string]
  let all_backups = toSeq(walkPattern(backup / "*.html.gz"))

  for i in all_backups:
    let (_, name, _) = splitFile(i)
    names.incl(backupFileName(name))

  var count = 0
  for i in names:
    for old in old_backups(backup, i):
      removeFile(old)
      count += 1

  return count

var
  port = 8000
  address = "127.0.0.1"
  dir = getCurrentDir()
  backup = "backup"
  title = "TW5 server"
  log = false
  maxbody = 100 # max body length (MB)
  configFile = "tw5server.json"
  configStr = "{}"

for kind, key, val in parseopt.getopt():
  case kind
  of cmdArgument:
    continue
  of cmdShortOption, cmdLongOption:
    case key
    of "h", "help":
      echo usage
      quit()
    of "c":
      configFile = val
    of "a", "address":
      address = val
    of "p", "port":
      port = parseInt(val)
    of "d", "dir":
      dir = val
    of "b", "backup":
      backup = val
    of "l", "log":
      log = true
    of "m", "max":
      maxbody = parseInt(val)
    of "v", "version":
      echo version
      quit()
  else:
    assert(false)

if configFile.fileExists:
  configStr = configFile.readFile

let config = parseJson(configStr)

dir = config{"server_path"}.getStr(dir)
address = config{"address"}.getStr(address)
port = config{"port"}.getInt(port)
title = config{"title"}.getStr(title)
backup = config{"backup"}.getStr(backup)

var settings: NimHttpSettings
settings.directory = dir
settings.mimes = newMimetypes()
settings.mimes.register("htm", "text/html")
settings.address = address
settings.name = name
settings.title = title
settings.version = version
settings.port = Port(port)

echo(" Serving url: ", address, ":", port)
echo("Serving path: ", dir)

if not ("/" in backup or "\\" in backup):
  backup = dir / backup
echo("  Backup dir: ", backup)

createDir(backup)

proc handleCtrlC() {.noconv.} =
  write(stdout, "\rClean backups (y to clean): ")
  let clean = readLine(stdin)

  var cleaned = 0
  if "y" == clean:
    cleaned = clean_backup(backup)

  if cleaned > 0:
    echo(cleaned, " backup(s) cleaned. Bye ~")
  else:
    echo("No backups were cleaned. Bye ~")

  quit()

setControlCHook(handleCtrlC)

maxbody = config{"max_body"}.getInt(maxbody)
log = config{"log"}.getBool(log)

serve(settings, backup, log, maxbody = maxbody * 1024 * 1024)
runForever()
