"""Build www/index.html (offline APK page) from the single-file game source."""
import re, sys
src, out = sys.argv[1], sys.argv[2]
s = open(src).read()
s = s.replace('https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js', 'vendor/three.min.js')
s = s.replace('https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/loaders/GLTFLoader.js', 'vendor/GLTFLoader.js')
s = re.sub(r'(<script src="https://cdn\.jsdelivr\.net/npm/three@0\.128\.0/examples/js/(shaders|postprocessing)/[^"]+"></script>\n?)+', '<script src="vendor/post.js"></script>\n', s)
head = '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">\n<meta name="theme-color" content="#0b1510">\n'
i = s.index('<canvas id="c">')
open(out, 'w').write(head + s[:i] + '</head>\n<body>\n' + s[i:] + '\n</body>\n</html>\n')
