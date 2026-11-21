#!/usr/bin/env python3
"""Renders the site's product stills for every locale: the iPhone camera prompter (prompter-render, from the
app's shared code) and the Mac notch panel (drawn by the Mac app itself, SIGHTLINE_RENDER_FRAMES), each in its
Apple bezel. Usage: render-all.py scripts.json out_dir [locale ...]"""
import json, os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'site/assets/img/src')
RENDER = '/tmp/claude-502/render-build/release/prompter-render'
MAC = '/tmp/claude-502/spm-build/debug/SightlinePrompter'
IPHONE_FRAME = os.path.join(SRC, 'devices/iphone-frame-portrait.png')
CAM_DOT = (843, 165)  # Dynamic Island, right of the front camera, in the 1350 x 2760 portrait bezel
MAC_BEZEL = '/tmp/claude-502/bezel-png/MacBook Pro M5 14-inch Space Black.png'

SPEECH = {'en': 'en-US', 'tr': 'tr-TR', 'de': 'de-DE', 'es': 'es-ES', 'fr': 'fr-FR', 'it': 'it-IT', 'pt-br': 'pt-BR',
          'ja': 'ja-JP', 'ko': 'ko-KR', 'zh-hans': 'zh-CN', 'zh-hant': 'zh-TW'}
# Finder's menu titles and the menu bar clock as macOS shows them in each language.
MENUS = {
    'en': ('Finder,File,Edit,View,Go,Window,Help', 'Fri 21 Nov  9:41'),
    'tr': ('Finder,Dosya,Düzen,Görüntü,Git,Pencere,Yardım', 'Cum 21 Kas  09:41'),
    'de': ('Finder,Ablage,Bearbeiten,Darstellung,Gehe zu,Fenster,Hilfe', 'Fr. 21. Nov.  09:41'),
    'es': ('Finder,Archivo,Edición,Visualización,Ir,Ventana,Ayuda', 'vie 21 nov  9:41'),
    'fr': ('Finder,Fichier,Édition,Présentation,Aller,Fenêtre,Aide', 'ven. 21 nov.  09:41'),
    'it': ('Finder,File,Composizione,Vista,Vai,Finestra,Aiuto', 'ven 21 nov  09:41'),
    'pt-br': ('Finder,Arquivo,Editar,Visualizar,Ir,Janela,Ajuda', 'sex. 21 de nov.  09:41'),
    'ja': ('Finder,ファイル,編集,表示,移動,ウインドウ,ヘルプ', '11月21日(金)  9:41'),
    'ko': ('Finder,파일,편집,보기,이동,윈도우,도움말', '11월 21일 (금) 오전 9:41'),
    'zh-hans': ('访达,文件,编辑,显示,前往,窗口,帮助', '11月21日 周五  09:41'),
    'zh-hant': ('Finder,檔案,編輯,顯示方式,前往,視窗,輔助說明', '11月21日 週五 上午9:41'),
}


def run(*args, **kw):
    subprocess.run(args, check=True, **kw)


def iphone(locale, script, out):
    work = f'{out}/work/{locale}'
    cfg = {'out': work, 'script': script, 'language': SPEECH[locale], 'fontSize': 35.5,
           'background': os.path.join(SRC, 'backdrop-talking.png'), 'stillAt': 3.4, 'recordStart': 3}
    path = f'{work}.json'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(cfg, open(path, 'w'), ensure_ascii=False)
    run(RENDER, path, stdout=subprocess.DEVNULL)
    # Screen rect of the 1350 x 2760 bezel (devices/README.md): 5.333 %, 2.5 %, 89.333 % x 95 %.
    w, h = 1206, 2622
    run('magick', f'{work}/still.png', '-resize', f'{w}x{h}!', '(', '-size', f'{w}x{h}', 'xc:none', '-fill', 'white', '-draw',
        f'roundrectangle 0,0,{w - 1},{h - 1},{round(w * .172)},{round(h * .079)}', ')', '-compose', 'DstIn', '-composite', f'{work}-screen.png')
    # The camera-in-use dot iOS shows in the Dynamic Island, right of the lens.
    run('magick', '-size', '1350x2760', 'xc:none', f'{work}-screen.png', '-geometry', '+72+69', '-composite', IPHONE_FRAME, '-composite',
        '-fill', '#30D158', '-draw', f'circle {CAM_DOT[0]},{CAM_DOT[1]} {CAM_DOT[0] + 8},{CAM_DOT[1]}', f'{out}/{locale}-iphone.png')


def mac(locale, script, out, mode='meeting'):
    work = f'{out}/work/{locale}-mac-{mode}'
    lib = f'{out}/work/maclib'
    run('rm', '-rf', work, lib)
    os.makedirs(lib)
    run('defaults', 'write', 'SightlinePrompter', 'script', '-string', script)
    run('defaults', 'write', 'SightlinePrompter', 'scriptLanguage', '-string', SPEECH[locale])
    run('defaults', 'write', 'SightlinePrompter', 'activeScriptID', '-string', '')
    env = dict(os.environ, SIGHTLINE_DEV='1', SIGHTLINE_LIBRARY_DIR=lib, SIGHTLINE_DEMO_SPEECH='0',
               SIGHTLINE_RENDER_FRAMES=work, SIGHTLINE_RENDER_DELAY='7.5')
    subprocess.run(['timeout', '25', MAC], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    menus, clock = MENUS[locale]
    people = ['backdrop-youtube.png'] + (['backdrop-portrait.png', 'backdrop-course.png', 'backdrop-reels.png'] if mode == 'meeting' else [])
    run('swift', os.path.join(ROOT, 'site/render/mac-screen.swift'), f'{work}/f0002.png', ','.join(os.path.join(SRC, p) for p in people),
        f'{work}-screen.png', clock, menus, env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'))
    # The camera is on (the call or the recording uses it), so its green light next to the lens is lit.
    run('magick', '-size', '3860x2540', 'xc:none', f'{work}-screen.png', '-geometry', '+418+288', '-composite', MAC_BEZEL, '-composite',
        '-fill', '#30D158', '-draw', 'circle 1957,351 1960,351', f'{out}/{locale}-mac{"" if mode == "meeting" else "-rec"}.png')


if __name__ == '__main__':
    scripts = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    for locale in sys.argv[3:] or list(SPEECH):
        iphone(locale, scripts[locale]['youtube'], out)
        mac(locale, scripts[locale]['meeting'], out)
        mac(locale, scripts[locale]['youtube'], out, 'record')
        print('done', locale, flush=True)


def snap(size):
    """TextSizeController.snap: the 20 pt x 1.10^n grid, rounded to half a point."""
    import math
    steps = round(math.log(size / 20) / math.log(1.10))
    return round(20 * 1.10 ** steps * 2) / 2


def distance_size(cm, width=354.0, ppmm=6.037):
    """PrompterTypography.plan for the iPhone 17 Pro portrait camera column (354 pt), then the controller's grid."""
    import math
    ideal = cm * 10 * math.tan(math.radians(.40)) * ppmm / .526
    return snap(max(min(ideal, width / (.5 * 13)), 20))


def distance_frames(locale, script, out, cms=range(35, 101, 5), cursor=4):
    """One still per distance: the front camera picture zoomed about the face as the phone moves away, and the
    text at the size the app commits there."""
    work = f'{out}/work/{locale}-dist'
    os.makedirs(work, exist_ok=True)
    photo = os.path.join(SRC, 'backdrop-talking.png')
    w, h = (int(v) for v in subprocess.run(['magick', 'identify', '-format', '%w %h', photo], capture_output=True, text=True).stdout.split())
    fx, fy = .5 * w, .37 * h
    sizes = {}
    for cm in cms:
        # A face's picture shrinks as 1 / distance: 1.6x at 35 cm down to the photo as taken at 100 cm, face kept centred.
        zoom = 32.31 / cm + 0.677
        cw, ch = w / zoom, h / zoom
        x, y = min(max(fx - cw / 2, 0), w - cw), min(max(fy - ch / 2, 0), h - ch)
        bg = f'{work}/bg{cm}.png'
        run('magick', photo, '-crop', f'{cw:.0f}x{ch:.0f}+{x:.0f}+{y:.0f}', '+repage', bg)
        size = distance_size(cm)
        sizes[cm] = size
        cfg = {'out': f'{work}/{cm}', 'script': script, 'language': SPEECH[locale], 'fontSize': size, 'background': bg,
               'cursor': cursor, 'recordStart': 4}
        json.dump(cfg, open(f'{work}/{cm}.json', 'w'), ensure_ascii=False)
        run(RENDER, f'{work}/{cm}.json', stdout=subprocess.DEVNULL)
        run('magick', f'{work}/{cm}/still.png', '-resize', '603x1311!', '-quality', '82', f'{out}/{locale}-dist-{cm}.webp')
    return sizes


def video(locale, script, out, seconds=12):
    """The hero loop: the camera prompter while the speaker reads, 30 fps, 720 x 1564 like the old capture."""
    work = f'{out}/work/{locale}-video'
    run('rm', '-rf', work)
    cfg = {'out': work, 'script': script, 'language': SPEECH[locale], 'fontSize': 35.5, 'scale': 2,
           'background': os.path.join(SRC, 'backdrop-talking.png'), 'duration': seconds, 'recordStart': 3}
    json.dump(cfg, open(f'{work}.json', 'w'), ensure_ascii=False)
    run(RENDER, f'{work}.json', stdout=subprocess.DEVNULL)
    base = f'{out}/video/{locale}'
    os.makedirs(base, exist_ok=True)
    scale = 'scale=720:1564:flags=lanczos'
    run('ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30', '-i', f'{work}/f%04d.png', '-vf', scale, '-c:v', 'libx264', '-pix_fmt',
        'yuv420p', '-crf', '24', '-preset', 'slow', '-movflags', '+faststart', '-an', f'{base}/demo-portrait.mp4')
    run('ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30', '-i', f'{work}/f%04d.png', '-vf', scale, '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuv420p', '-b:v', '0',
        '-crf', '38', '-row-mt', '1', '-an', f'{base}/demo-portrait.webm')
    run('magick', f'{work}/f0090.png', '-resize', '720x1564!', '-quality', '82', f'{base}/demo-portrait-poster.webp')
    run('rm', '-rf', work)


RENDER2 = '/tmp/claude-502/render-build2/release/prompter-render'
# Use-case tabs: which script, picture and orientation each one shows (screen only; the page adds the bezel).
CASES = {'youtube': ('youtube', 'backdrop-youtube.png', True, 12), 'reels': ('reels', 'backdrop-reels.png', False, 6),
         'course': ('course', 'backdrop-course.png', False, 9)}


def cases(locale, scripts, out):
    for case, (key, photo, landscape, cursor) in CASES.items():
        work = f'{out}/work/{locale}-case-{case}'
        size = {'width': 874, 'height': 402, 'insets': [0, 62, 21, 62]} if landscape else {}
        cfg = {'out': work, 'script': scripts[key], 'language': SPEECH[locale], 'fontSize': 35.5, 'background': os.path.join(SRC, photo),
               'cursor': cursor, 'recordStart': 37, 'roll': 0, 'pitch': 1, **size}
        json.dump(cfg, open(f'{work}.json', 'w'), ensure_ascii=False)
        run(RENDER2, f'{work}.json', stdout=subprocess.DEVNULL)
        run('magick', f'{work}/still.png', '-quality', '84', f'{out}/{locale}-case-{case}.webp')
    # The meeting tab shows the Mac in a video call.
    run('magick', f'{out}/{locale}-mac.png', '-resize', '1600x', '-quality', '84', f'{out}/{locale}-case-meeting.webp')


def video_landscape(locale, script, out, seconds=10):
    """The crop-guide loop: landscape recording with the 9:16 guide, 1600 x 736 like the old capture."""
    work = f'{out}/work/{locale}-videol'
    run('rm', '-rf', work)
    cfg = {'out': work, 'script': script, 'language': SPEECH[locale], 'fontSize': 35.5, 'scale': 2, 'width': 874, 'height': 402,
           'insets': [0, 62, 21, 62], 'background': os.path.join(SRC, 'backdrop-youtube.png'), 'duration': seconds, 'recordStart': 19,
           'roll': 0, 'pitch': 1}
    json.dump(cfg, open(f'{work}.json', 'w'), ensure_ascii=False)
    run(RENDER2, f'{work}.json', stdout=subprocess.DEVNULL)
    base = f'{out}/video/{locale}'
    os.makedirs(base, exist_ok=True)
    scale = 'scale=1600:736:flags=lanczos'
    run('ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30', '-i', f'{work}/f%04d.png', '-vf', scale, '-c:v', 'libx264', '-pix_fmt',
        'yuv420p', '-crf', '24', '-preset', 'slow', '-movflags', '+faststart', '-an', f'{base}/demo-landscape.mp4')
    run('ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30', '-i', f'{work}/f%04d.png', '-vf', scale, '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuv420p',
        '-b:v', '0', '-crf', '38', '-row-mt', '1', '-an', f'{base}/demo-landscape.webm')
    run('magick', f'{work}/f0090.png', '-resize', '1600x736!', '-quality', '82', f'{base}/demo-landscape-poster.webp')
    run('rm', '-rf', work)


def encode(frames, base, name, size, poster_frame=90):
    """frames: a printf pattern of PNGs. Writes base/name.mp4, .webm and -poster.webp at size (WxH)."""
    os.makedirs(base, exist_ok=True)
    scale = f'scale={size.replace("x", ":")}:flags=lanczos'
    run('ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30', '-i', frames, '-vf', scale, '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
        '-crf', '24', '-preset', 'slow', '-movflags', '+faststart', '-an', f'{base}/{name}.mp4')
    run('ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30', '-i', frames, '-vf', scale, '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuv420p',
        '-b:v', '0', '-crf', '38', '-row-mt', '1', '-an', f'{base}/{name}.webm')
    run('magick', frames % poster_frame, '-resize', f'{size}!', '-quality', '82', f'{base}/{name}-poster.webp')


def iphone_video(locale, name, script, photo, landscape, out, seconds=10):
    """A camera-mode loop from prompter-render: the speaker reads and the prompter follows word by word."""
    work = f'{out}/work/{locale}-{name}'
    run('rm', '-rf', work)
    size = {'width': 874, 'height': 402, 'insets': [0, 62, 21, 62]} if landscape else {}
    cfg = {'out': work, 'script': script, 'language': SPEECH[locale], 'fontSize': 35.5, 'scale': 2, 'background': os.path.join(SRC, photo),
           'duration': seconds, 'recordStart': 37, 'roll': 0, 'pitch': 1, **size}
    json.dump(cfg, open(f'{work}.json', 'w'), ensure_ascii=False)
    run(RENDER2, f'{work}.json', stdout=subprocess.DEVNULL)
    encode(f'{work}/f%04d.png', f'{out}/video/{locale}', name, '1600x736' if landscape else '720x1564')
    run('rm', '-rf', work)


def mac_video(locale, script, out, mode, seconds=10):
    """The Mac screen as a loop: the desktop and window drawn once, the app's own panel frames (30 a second) on top.
    Only the screen; the page lays Apple's bezel over it, as it does for the iPhone."""
    work = f'{out}/work/{locale}-macv-{mode}'
    lib = f'{out}/work/maclib-v'
    run('rm', '-rf', work, lib)
    os.makedirs(lib)
    run('defaults', 'write', 'SightlinePrompter', 'script', '-string', script)
    run('defaults', 'write', 'SightlinePrompter', 'scriptLanguage', '-string', SPEECH[locale])
    run('defaults', 'write', 'SightlinePrompter', 'activeScriptID', '-string', '')
    env = dict(os.environ, SIGHTLINE_DEV='1', SIGHTLINE_LIBRARY_DIR=lib, SIGHTLINE_DEMO_SPEECH='0', SIGHTLINE_RENDER_FRAMES=work,
               SIGHTLINE_RENDER_SECONDS=str(seconds), SIGHTLINE_RENDER_DELAY='1.6')
    subprocess.run(['timeout', str(int(seconds) + 30), MAC], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    menus, clock = MENUS[locale]
    people = (['backdrop-youtube.png@0.64', 'call-1.png', 'call-2.png', 'call-3.png'] if mode == 'meeting' else ['backdrop-youtube.png'])
    run('swift', os.path.join(ROOT, 'site/render/mac-screen.swift'), 'none', ','.join(os.path.join(SRC, p) for p in people),
        f'{work}-bg.png', clock, menus, env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'))
    # Panel 520 x 220 pt at 2x, centred under the notch: x = (1512 - 520) / 2 pt.
    comp = f'{work}/c'
    os.makedirs(comp)
    run('ffmpeg', '-y', '-loglevel', 'error', '-loop', '1', '-i', f'{work}-bg.png', '-framerate', '30', '-i', f'{work}/f%04d.png',
        '-filter_complex', '[0][1]overlay=992:0:shortest=1', f'{comp}/f%04d.png')
    encode(f'{comp}/f%04d.png', f'{out}/video/{locale}', f'mac-{mode}', '1512x982')
    run('rm', '-rf', work)


LIVE = os.path.join(ROOT, 'site/assets/img/live')
# Stills under the live prompter: the camera picture and the app's chrome, no text (the page draws it).
STILLS = {'talking': ('backdrop-talking.png', False), 'reels': ('backdrop-reels.png', False), 'course': ('backdrop-course.png', False),
          'youtube-l': ('backdrop-youtube.png', True)}


def live_stills(out):
    os.makedirs(LIVE, exist_ok=True)
    for name, (photo, landscape) in STILLS.items():
        work = f'{out}/work/live-{name}'
        size = {'width': 874, 'height': 402, 'insets': [0, 62, 21, 62]} if landscape else {}
        cfg = {'out': work, 'script': 'x', 'text': False, 'background': os.path.join(SRC, photo), 'cursor': 0, 'recordStart': 6,
               'roll': 0, 'pitch': 1, **size}
        json.dump(cfg, open(f'{work}.json', 'w'))
        run(RENDER2, f'{work}.json', stdout=subprocess.DEVNULL)
        run('magick', f'{work}/still.png', '-quality', '84', f'{LIVE}/iphone-{name}.webp')
    # the distance scene: the face's picture at 1 / distance, every 5 cm
    photo = os.path.join(SRC, 'backdrop-talking.png')
    w, h = (int(v) for v in subprocess.run(['magick', 'identify', '-format', '%w %h', photo], capture_output=True, text=True).stdout.split())
    for cm in range(35, 101, 5):
        zoom = 32.31 / cm + 0.677
        cw, ch = w / zoom, h / zoom
        x, y = min(max(.5 * w - cw / 2, 0), w - cw), min(max(.37 * h - ch / 2, 0), h - ch)
        work = f'{out}/work/live-d{cm}'
        run('magick', photo, '-crop', f'{cw:.0f}x{ch:.0f}+{x:.0f}+{y:.0f}', '+repage', f'{work}.png')
        json.dump({'out': work, 'script': 'x', 'text': False, 'background': f'{work}.png', 'cursor': 0, 'recordStart': 8, 'roll': 0, 'pitch': 1},
                  open(f'{work}.json', 'w'))
        run(RENDER2, f'{work}.json', stdout=subprocess.DEVNULL)
        run('magick', f'{work}/still.png', '-resize', '804x1748', '-quality', '82', f'{LIVE}/dist-{cm}.webp')
    for l in SPEECH:
        menus, clock = MENUS[l]
        os.makedirs(f'{LIVE}/{l}', exist_ok=True)
        for mode, people in (('meeting', ['backdrop-youtube.png@0.64', 'call-1.png', 'call-2.png', 'call-3.png']), ('record', ['backdrop-youtube.png'])):
            run('swift', os.path.join(ROOT, 'site/render/mac-screen.swift'), 'none', ','.join(os.path.join(SRC, p) for p in people),
                f'{out}/work/mac-{l}-{mode}.png', clock, menus, env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'))
            run('magick', f'{out}/work/mac-{l}-{mode}.png', '-resize', '2268x', '-quality', '84', f'{LIVE}/{l}/mac-{mode}.webp')


def live_words(scripts):
    """The approved scripts split into words by the app's ScriptTokenizer, for prompter.js."""
    words = {}
    for l in SPEECH:
        words[l] = {}
        for key, text in scripts[l].items():
            path = f'/tmp/claude-502/r7/work-dump.json'
            json.dump({'out': '/tmp/x', 'script': text, 'language': SPEECH[l], 'dump': True}, open(path, 'w'), ensure_ascii=False)
            words[l][key] = json.loads(subprocess.run([RENDER2, path], capture_output=True, text=True, check=True).stdout)
    json.dump(words, open(os.path.join(ROOT, 'site/render/prompter-words.json'), 'w'), ensure_ascii=False, indent=1)
