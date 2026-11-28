import numpy as np

SR = 44100
BPM = 75.0
beat = 60.0 / BPM            # 0.8 s
bar = 4 * beat               # 3.2 s
BARS = 16
T = BARS * bar               # 51.2 s —— 整数拍，天然无缝
N = int(round(SR * T))
t = np.arange(N) / SR
rng = np.random.default_rng(11)
buf = {k: np.zeros(N) for k in ("bass", "pad", "mel", "arp", "heart", "wash")}

def add(name, start, sig):
    i0 = int(round(start * SR)) % N
    idx = (i0 + np.arange(len(sig))) % N
    np.add.at(buf[name], idx, sig)

def adsr(n, a, d, s, r, sr=SR):
    k = np.arange(n) / sr
    tot = n / sr
    env = np.ones(n) * s
    env = np.where(k < a, k / max(a, 1e-6), env)
    m = (k >= a) & (k < a + d)
    env = np.where(m, 1.0 + (s - 1.0) * (k - a) / max(d, 1e-6), env)
    m = k > tot - r
    env = np.where(m, s * np.clip((tot - k) / max(r, 1e-6), 0, 1), env)
    return env

def tone(f, dur, harm, env, detune=0.0, vib=0.0):
    n = int(dur * SR)
    k = np.arange(n) / SR
    out = np.zeros(n)
    fm = f * (1.0 + vib * np.sin(2 * np.pi * 4.6 * k)) if vib else f
    for h, a in harm:
        out += a * np.sin(2 * np.pi * fm * h * k)
        if detune:
            out += a * 0.6 * np.sin(2 * np.pi * fm * (1 + detune) * h * k)
    return out / (np.abs(out).max() + 1e-9) * env

# ---- 和声：D 小调，Dm – Bb – Gm – Am，每个和弦 2 小节，整圈 8 小节，跑两遍 ----
P = [
    dict(root=73.416,  tri=(146.83, 174.61, 220.00), arp=(293.66, 349.23, 440.00, 587.33)),  # Dm
    dict(root=58.270,  tri=(116.54, 146.83, 174.61), arp=(233.08, 293.66, 349.23, 466.16)),  # Bb
    dict(root=48.999,  tri=( 97.99, 116.54, 146.83), arp=(195.99, 233.08, 293.66, 391.99)),  # Gm
    dict(root=55.000,  tri=(110.00, 130.81, 164.81), arp=(220.00, 261.63, 329.63, 440.00)),  # Am
]
MEL = [(220.00, 174.61), (174.61, 146.83), (146.83, 195.99), (261.63, 220.00)]

for cyc in range(2):
    for ci, ch in enumerate(P):
        s0 = (cyc * 8 + ci * 2) * bar
        dur = 2 * bar + 1.3   # 和弦之间留重叠，否则每段之间会塌出一个空档，整体像在一鼓一瘪

        # 低音：根音，慢起慢收
        n = int(dur * SR)
        add("bass", s0, tone(ch["root"], dur, [(1, 1.0), (2, 0.28), (3, 0.08)],
                             adsr(n, 0.35, 1.0, 0.74, 1.2)) * 1.0)

        # 铺垫和弦：三和弦，很慢的涌起
        for j, f in enumerate(ch["tri"]):
            add("pad", s0 + j * 0.05, tone(f, dur, [(1, 1.0), (2, 0.34), (3, 0.16), (4, 0.07)],
                                           adsr(n, 0.9, 0.9, 0.82, 1.3), detune=0.0016) * 0.52)

        # 爬音：短促拨奏，只在第 2 小节，不抢拍
        if cyc == 0 or ci % 2 == 1:
            for j, f in enumerate(ch["arp"]):
                st = s0 + bar + j * (beat / 2)
                m = int(0.9 * SR)
                env = np.exp(-np.arange(m) / SR / 0.19)
                add("arp", st, tone(f, 0.9, [(1, 1.0), (2, 0.42), (3, 0.14)], env) * (0.95 - 0.1 * j))

        # 主旋律：只在后半圈出现，让 51 秒有个起伏
        if cyc == 1:
            f1, f2 = MEL[ci]
            n1, n2 = int(5 * beat * SR), int(3 * beat * SR)
            add("mel", s0, tone(f1, 5 * beat, [(1, 1.0), (2, 0.42), (3, 0.17), (4, 0.06)],
                                adsr(n1, 0.35, 0.5, 0.75, 0.6), vib=0.004))
            add("mel", s0 + 5 * beat, tone(f2, 3 * beat, [(1, 1.0), (2, 0.40), (3, 0.15)],
                                           adsr(n2, 0.3, 0.4, 0.72, 0.5), vib=0.004))

# ---- 心跳 75 BPM ----
def pink(n):
    x = rng.normal(0, 1, n)
    return np.convolve(x, np.ones(24) / 24.0, mode="same")

for i in range(int(round(T / beat))):
    s = i * beat
    br = 0.85 + 0.15 * np.sin(2 * np.pi * s / 25.6)
    for off, amp, tau, fh, fl in ((0.0, 1.0, 0.058, 68.0, 36.0), (0.32 * beat, 0.50, 0.044, 56.0, 33.0)):
        m = int(0.45 * SR)
        k = np.arange(m) / SR
        f = fl + (fh - fl) * np.exp(-k / 0.055)
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-k / tau)
        thud = pink(m) * np.exp(-k / 0.013) * 0.42 * np.clip(k / 0.001, 0, 1)
        add("heart", s + off, amp * br * (body + thud))

# ---- 体液涌动（频域生成 → 严格以 T 为周期）----
nf = N // 2 + 1
fr = np.fft.rfftfreq(N, 1.0 / SR)
mag = np.exp(-((np.log((fr + 1e-6) / 240.0)) ** 2) / 1.1) / (1 + (fr / 2600.0) ** 2)
sp = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, nf)); sp[0] = 0
w = np.fft.irfft(sp, n=N); w /= np.abs(w).max()
buf["wash"] = w * (0.30 + 0.70 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 25.6)))

for k in buf:
    buf[k] /= (np.abs(buf[k]).max() + 1e-9)

mix = (0.40 * buf["bass"] + 0.30 * buf["pad"] + 0.16 * buf["mel"]
       + 0.11 * buf["arp"] + 0.30 * buf["heart"] + 0.11 * buf["wash"])

sp = np.fft.rfft(mix)
sp *= 1.0 / (1.0 + (26.0 / np.maximum(np.fft.rfftfreq(N, 1.0 / SR), 1e-6)) ** 4)
mix = np.fft.irfft(sp, n=N)
mix = np.tanh(mix * 1.2) / np.tanh(1.2)
mix *= 0.62 / (np.abs(mix).max() + 1e-12)
print(f"{T:.2f}s  峰值 {np.abs(mix).max():.3f}  RMS {20*np.log10(np.sqrt((mix**2).mean())):.1f} dBFS")
print(f"接缝跳变 {abs(mix[0]-mix[-1]):.5f}  平均 {np.abs(np.diff(mix)).mean():.5f}")

st = np.stack([mix, np.roll(mix, int(0.005 * SR))], axis=1)
st *= 0.62 / (np.abs(st).max() + 1e-12)
np.save("mix2.npy", st.astype(np.float32))
