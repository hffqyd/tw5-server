#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler, SimpleHTTPRequestHandler
import sys
import getopt
import os
import datetime
import gzip
import glob

usage = """
python tw5-server.py -a localhost -p 8000 -d ./ -b backup

-h usage help
-a address, defautl localhost
-p port, default 8000
-d directory to servering, default `current dir`
-b backup directory name, default `backup`

Backups auto-clean strategy: 
Keep all backups in current month, keep only the newest one for previous months.
"""

addr = "localhost"
port = 8000
root = os.getcwd()
backup = "backup"

opts, args = getopt.getopt(sys.argv[1:], "-h-a:-p:-d:-b:")
# parse args
for opt_name, opt_value in opts:
    if opt_name in ("-h"):
        print("Help:")
        print(usage)
        sys.exit()
    elif opt_name in ("-a"):
        addr = opt_value
    elif opt_name in ("-p"):
        port = int(opt_value)
    elif opt_name in ("-d"):
        root = os.path.abspath(opt_value)
    elif opt_name in ("-b"):
        backup = opt_value
    else:
        print("Usage:")
        print(usage)
        sys.exit()


def time_now():
    return datetime.datetime.now().strftime("%Y%m%d%H%M%S")


class TWiki5(SimpleHTTPRequestHandler):
    backup = backup

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def do_PUT(self):
        # file path
        file = self.translate_path(self.path)
        root = os.path.split(file)[0]
        # content
        length = int(self.headers['Content-Length'])
        put_content = self.rfile.read(length)
        self.send_response(201, "Saved")
        self.end_headers()

        # update current file
        with open(file, 'wb') as current_f:
            current_f.write(put_content)
        print("Update:", file)

        # backup
        back_name = os.path.basename(file).split('.')[0] + "-" + time_now()
        # create back dir
        backup = os.path.join(root, self.backup)
        if not os.path.exists(backup):
            os.mkdir(backup)

        back_name = os.path.join(backup, back_name+".html.gz")
        with gzip.open(back_name, 'wb') as w:
            w.write(put_content)
        print("Backup to:", back_name)

    def do_OPTIONS(self):
        self.send_response(200, "ok")
        self.send_header("dav", "tw5/put")
        self.send_header("allow", "GET,HEAD,POST,OPTIONS,CONNECT,PUT,DAV,dav")
        self.send_header("x-api-access-type", "file")
        self.end_headers()

def old_backups(path, name):
    now = time_now()
    c_year_month = now[:6]

    backup_name = os.path.join(path, name)
    all_backup = glob.glob(backup_name + '*.html.gz')
    all_backup = sorted(all_backup, reverse=True)

    to_be_removed = []
    saved_y_m = ''
    for i in all_backup:
        date = i[-22:]
        y_m = date[:6]
        if y_m >= c_year_month:
            continue

        if saved_y_m == y_m:
            to_be_removed.append(i)
        else:
            saved_y_m = y_m

    return to_be_removed

def clean_backup(path):
    names = set()
    all_backups = glob.glob(os.path.join(path, '*.html.gz'))
    for i in all_backups:
        name = os.path.split(i)[1]
        name = name[:-23]
        names.add(name)

    count = 0
    for i in names:
        for old in old_backups(path, i):
            os.remove(old)
            print('Removing', old)
            count += 1
    return count

if __name__ == "__main__":
    server = (addr, port)
    print(f"Servering at {addr}:{port}")
    print(f'tiddly wiki path: {root}')

    try:
        HTTPServer(server, TWiki5).serve_forever()
    except KeyboardInterrupt:
        clean = input('\rClean backups (y to clean): ')

        cleaned = 0
        if 'y' == clean:
            cleaned = clean_backup(backup)

        if cleaned > 0:
            print(cleaned, 'backup(s) cleaned. Bye ~')
        else:
            print('No backups were cleaned. Bye ~')

        sys.exit()
