#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler, SimpleHTTPRequestHandler
import sys
import getopt
import os
import datetime
import gzip

usage = """
python tw5-server.py -a localhost -p 8000 -d ./ -b tmp

-p port, default 8000
-d directory to servering, default `current dir`
-b backup directory name, default `tmp`
"""

addr = "localhost"
port = 8000
root = os.getcwd()
backup = "tmp"

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

backup = os.path.join(root, backup)


def time_now():
    return datetime.datetime.now().strftime("%Y%m%d%H%M%S")


class TWiki5(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def do_PUT(self):
        # file path
        file = self.translate_path(self.path)
        # content
        length = int(self.headers['Content-Length'])
        put_content = self.rfile.read(length)
        self.send_response(201, "Saved")
        self.end_headers()

        # backup
        back_name = os.path.basename(file).split('.')[0] + "-" + time_now()
        # create back dir
        if not os.path.exists(backup):
            os.mkdir(backup)

        back_name = os.path.join(backup, back_name+".html.gz")
        with gzip.open(back_name, 'wb') as w:
            w.write(put_content)
        print("Backup: ", back_name)

        # update current file
        with open(file, 'wb') as current_f:
            current_f.write(put_content)
        print("Update: ", file)

    def do_OPTIONS(self):
        self.send_response(200, "ok")
        self.send_header("dav", "tw5/put")
        self.send_header("allow", "GET,HEAD,POST,OPTIONS,CONNECT,PUT,DAV,dav")
        self.send_header("x-api-access-type", "file")
        self.end_headers()


server = (addr, port)

if __name__ == "__main__":
    print(f"Servering at {addr}:{port}")
    try:
        HTTPServer(server, TWiki5).serve_forever()
    except KeyboardInterrupt:
        print("\rBye~")
        sys.exit()
