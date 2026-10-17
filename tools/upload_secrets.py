#!/usr/bin/env python3
"""upload_secrets.py — 把签名证书安全上传到 GitHub Actions Secrets

用法:
    python3 tools/upload_secrets.py <owner/repo> <cert.p12> <p12_password> <profile.mobileprovision>

示例:
    python3 tools/upload_secrets.py yoyo520956/OpenMinis-AutoPilot /tmp/cp/cert.p12 1 /tmp/cp/profile.mobileprovision

上传的 secrets:
    SIGNING_P12_BASE64       (base64 of .p12)
    SIGNING_P12_PASSWORD     (p12 password)
    SIGNING_PROFILE_BASE64   (base64 of .mobileprovision)

说明:
    - 值使用 libsodium sealed box 加密（GitHub 要求），密钥仅仓库可见
    - 证书内容不会被打印；PAT 从 /tmp/gh_pat.txt 或环境变量 GH_PAT 读取
    - 删除: python3 tools/upload_secrets.py --delete <owner/repo> [name...]
"""
import sys, os, base64, json, urllib.request, urllib.error

try:
    from nacl import encoding, public
except ImportError:
    print('✗ 需要 PyNaCl: pip install pynacl --break-system-packages')
    sys.exit(1)


def get_token():
    if os.environ.get('GH_PAT'):
        return os.environ['GH_PAT'].strip()
    with open('/tmp/gh_pat.txt') as f:
        return f.read().strip()


def api(method, url, token, data=None):
    req = urllib.request.Request(url, method=method)
    req.add_header('Authorization', 'token ' + token)
    req.add_header('Accept', 'application/vnd.github+json')
    if data is not None:
        req.add_header('Content-Type', 'application/json')
        body = json.dumps(data).encode()
    else:
        body = None
    try:
        with urllib.request.urlopen(req, body, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:400]


def encrypt(public_key_b64, secret_value):
    pk = public.PublicKey(public_key_b64.encode('utf-8'), encoding.Base64Encoder())
    sealed = public.SealedBox(pk).encrypt(secret_value.encode('utf-8'))
    return base64.b64encode(sealed).decode('utf-8')


def put_secret(repo, token, pk, kid, name, value):
    enc = encrypt(pk, value)
    st, resp = api('PUT',
                   'https://api.github.com/repos/%s/actions/secrets/%s' % (repo, name),
                   token, {'encrypted_value': enc, 'key_id': kid})
    ok = st in (201, 204)
    print(('✓' if ok else '✗'), name, st, '' if ok else resp)
    return ok


def main():
    args = sys.argv[1:]
    token = get_token()

    if len(args) >= 2 and args[0] == '--delete':
        repo = args[1]
        names = args[2:] or ['SIGNING_P12_BASE64', 'SIGNING_P12_PASSWORD', 'SIGNING_PROFILE_BASE64']
        for n in names:
            st, resp = api('DELETE', 'https://api.github.com/repos/%s/actions/secrets/%s' % (repo, n), token)
            print(('✓' if st == 204 else '✗'), 'deleted', n, st)
        return

    if len(args) != 4:
        print(__doc__)
        sys.exit(1)
    repo, p12, p12pass, profile = args

    for f in (p12, profile):
        if not os.path.exists(f):
            print('✗ 文件不存在:', f)
            sys.exit(1)

    st, key = api('GET', 'https://api.github.com/repos/%s/actions/secrets/public-key' % repo, token)
    if st != 200:
        print('✗ 获取仓库公钥失败:', st, key)
        sys.exit(1)
    pk, kid = key['key'], key['key_id']
    print('▶ 仓库公钥已获取 (key_id=%s…)' % kid[:8])

    values = {
        'SIGNING_P12_BASE64': base64.b64encode(open(p12, 'rb').read()).decode('ascii'),
        'SIGNING_P12_PASSWORD': p12pass,
        'SIGNING_PROFILE_BASE64': base64.b64encode(open(profile, 'rb').read()).decode('ascii'),
    }
    allok = True
    for name, val in values.items():
        allok = put_secret(repo, token, pk, kid, name, val) and allok
    print('▶ 完成' + (' ✓ 全部成功' if allok else ' ⚠ 有失败项'))


if __name__ == '__main__':
    main()
