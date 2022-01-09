# tw5-server

A local server for TiddlyWiki5 that saves and backups wikis, inspired by [tw5-server.rb](https://gist.github.com/jimfoltz/ee791c1bdd30ce137bc23cce826096da).

tw5-server is written in Python, provides features of:

Backup wiki in compress format (.gz).

# Usage

```bash
python script.py -p 8000 -d ./ -b tmp

-p port, default 8000
-d directory to servering, default `current dir`
-b backup directory name, default `tmp`
```

# Plans

- [ ] Upload images/files (e.g. to images directory) for use within TiddlyWiki5 (e.g. [img[images/some.png]])
