import numpy as np

SR = 44100
BPM = 75.0
beat = 60.0 / BPM
bar = 4 * beat                 # 3.2 s
BARS = 32
T = BARS * bar                 # 102.4 s
N = int(round(SR * T))
t = np.arange(N) / SR
rng = np.random.default_rng(23)
buf = {k: np.zeros(N) for k in ("bass", "pad", "mel", "arp", "heart", "wash")}

def add(name, start, sig):
    i0 = int(round(start * SR)) % N
    np.add.at(buf[name], (i0 + np.arange(len(sig))) % N, sig)

def adsr(n, a, d, s, r):
    k = np.arange(n) / SR; tot = n / SR
    e = np.full(n, s)
    e = np.where(k < a, k / max(a, 1e-6), e)
    m = (k >= a) & (k < a + d)
    e = np.where(m, 1.0 + (s - 1.0) * (k - a) / max(d, 1e-6), e)
    m = k > tot - r
    return np.where(m, s * np.clip((tot - k) / max(r, 1e-6), 0, 1), e)

def voice(f, dur, harm, env, detune=0.0):
    n = int(dur * SR); k = np.arange(n) / SR
    out = np.zeros(n)
    for h, a in harm:
        out += a * np.sin(2 * np.pi * f * h * k)
        if detune:
            out += a * 0.5 * np.sin(2 * np.pi * f * (1 + detune) * h * k)
    return out / (np.abs(out).max() + 1e-9) * env

def marimba(f, dur=1.4):
    """马林巴：基音 + 4 倍音 + 9.2 倍音（调音琴板的实际泛音比），快起快落，带一点槌击声"""
    n = int(dur * SR); k = np.arange(n) / SR
    tau = np.clip(0.55 * (220.0 / f) ** 0.5, 0.18, 0.75)
    out = (np.sin(2 * np.pi * f * k) * np.exp(-k / tau)
           + 0.40 * np.sin(2 * np.pi * f * 4.0 * k) * np.exp(-k / (tau * 0.30))
           + 0.12 * np.sin(2 * np.pi * f * 9.2 * k) * np.exp(-k / (tau * 0.12)))
    mallet = np.convolve(rng.normal(0, 1, n), np.ones(12) / 12, mode="same") * np.exp(-k / 0.004) * 0.18
    sig = (out + mallet) * np.clip(k / 0.0015, 0, 1)
    return sig / (np.abs(sig).max() + 1e-9)

P = [
    dict(root=73.416, tri=(146.83, 174.61, 220.00), arp=(293.66, 349.23, 440.00, 587.33, 440.00, 349.23)),  # Dm
    dict(root=58.270, tri=(116.54, 146.83, 174.61), arp=(233.08, 293.66, 349.23, 466.16, 349.23, 293.66)),  # Bb
    dict(root=48.999, tri=( 97.99, 116.54, 146.83), arp=(195.99, 233.08, 293.66, 391.99, 293.66, 233.08)),  # Gm
    dict(root=55.000, tri=(110.00, 130.81, 164.81), arp=(220.00, 261.63, 329.63, 440.00, 329.63, 261.63)),  # Am
]
MEL = [(220.00, 174.61), (174.61, 146.83), (146.83, 195.99), (261.63, 220.00)]

# 四段式：空 → 加爬音 → 加旋律 → 退回空。循环点是"空接空"，不会戛然而止
SEC = [dict(pad=0.55, arp=0.00, mel=0.0),
       dict(pad=0.85, arp=0.85, mel=0.0),
       dict(pad=1.00, arp=1.00, mel=1.0),
       dict(pad=0.80, arp=0.45, mel=0.45)]

for cyc in range(4):
    g = SEC[cyc]
    for ci, ch in enumerate(P):
        s0 = (cyc * 8 + ci * 2) * bar
        dur = 2 * bar + 1.3                      # 和弦之间重叠，避免塌出空档
        n = int(dur * SR)

        add("bass", s0, voice(ch["root"], dur, [(1, 1.0), (2, 0.18), (3, 0.04)],
                              adsr(n, 0.35, 1.0, 0.74, 1.2)))

        for j, f in enumerate(ch["tri"]):        # pad：开发者说 pad 很好，加重
            add("pad", s0 + j * 0.06,
                voice(f, dur, [(1, 1.0), (2, 0.30), (3, 0.13), (4, 0.05)],
                      adsr(n, 1.0, 0.9, 0.82, 1.4),
                      detune=0.0008 if j == 2 else 0.0) * g["pad"] * 0.55)

        if g["arp"] > 0:                         # 马林巴爬音
            fade = 1.0 if cyc != 3 else max(0.0, 1.0 - ci / 3.0)
            for j, f in enumerate(ch["arp"]):
                add("arp", s0 + bar + j * (beat / 2),
                    marimba(f) * g["arp"] * fade * (0.95 - 0.07 * j))

        if g["mel"] > 0:                         # 旋律：软 pad 音色，无颤音
            fade = 1.0 if cyc != 3 else max(0.0, 1.0 - ci / 2.0)
            f1, f2 = MEL[ci]
            n1, n2 = int(5 * beat * SR), int(3 * beat * SR)
            add("mel", s0, voice(f1, 5 * beat, [(1, 1.0), (2, 0.30), (3, 0.10)],
                                 adsr(n1, 0.8, 0.5, 0.80, 1.0)) * g["mel"] * fade)
            add("mel", s0 + 5 * beat, voice(f2, 3 * beat, [(1, 1.0), (2, 0.28), (3, 0.09)],
                                            adsr(n2, 0.7, 0.4, 0.78, 0.8)) * g["mel"] * fade)

def pink(n):
    return np.convolve(rng.normal(0, 1, n), np.ones(24) / 24.0, mode="same")

for i in range(int(round(T / beat))):
    s = i * beat
    br = 0.85 + 0.15 * np.sin(2 * np.pi * s / 25.6)
    for off, amp, tau, fh, fl in ((0.0, 1.0, 0.058, 68.0, 36.0), (0.32 * beat, 0.50, 0.044, 56.0, 33.0)):
        m = int(0.45 * SR); k = np.arange(m) / SR
        f = fl + (fh - fl) * np.exp(-k / 0.055)
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-k / tau)
        thud = pink(m) * np.exp(-k / 0.013) * 0.42 * np.clip(k / 0.001, 0, 1)
        add("heart", s + off, amp * br * (body + thud))

nf = N // 2 + 1
fr = np.fft.rfftfreq(N, 1.0 / SR)
mag = np.exp(-((np.log((fr + 1e-6) / 240.0)) ** 2) / 1.1) / (1 + (fr / 2600.0) ** 2)
sp = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, nf)); sp[0] = 0
w = np.fft.irfft(sp, n=N); w /= np.abs(w).max()
buf["wash"] = w * (0.30 + 0.70 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 51.2)))

for k in buf:
    buf[k] /= (np.abs(buf[k]).max() + 1e-9)

mix = (0.34 * buf["bass"] + 0.42 * buf["pad"] + 0.17 * buf["mel"]
       + 0.16 * buf["arp"] + 0.26 * buf["heart"] + 0.10 * buf["wash"])
sp = np.fft.rfft(mix)
sp *= 1.0 / (1.0 + (26.0 / np.maximum(np.fft.rfftfreq(N, 1.0 / SR), 1e-6)) ** 4)
mix = np.fft.irfft(sp, n=N)
mix = np.tanh(mix * 1.2) / np.tanh(1.2)
mix *= 0.62 / (np.abs(mix).max() + 1e-12)
print(f"{T:.1f}s  峰值 {np.abs(mix).max():.3f}  RMS {20*np.log10(np.sqrt((mix**2).mean())):.1f} dBFS")
print(f"接缝跳变 {abs(mix[0]-mix[-1]):.5f}  平均相邻 {np.abs(np.diff(mix)).mean():.5f}")
w2 = int(1.0 * SR)
r = np.array([np.sqrt((mix[i:i+w2]**2).mean()) for i in range(0, N - w2, w2)])
print("每段 RMS(dB)：", " ".join(f"{20*np.log10(r[i*25:(i+1)*25].mean()):.1f}" for i in range(4)))
st = np.stack([mix, np.roll(mix, int(0.005 * SR))], axis=1)
st *= 0.62 / (np.abs(st).max() + 1e-12)
np.save("mix3.npy", st.astype(np.float32))
