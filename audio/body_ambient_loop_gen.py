import numpy as np

SR = 44100
T = 50.0                      # 循环长度（秒）
N = int(SR * T)
t = np.arange(N) / SR
BPM = 72.0
beat = 60.0 / BPM             # 0.8333 s，60 拍正好 50 秒 → 无缝循环
rng = np.random.default_rng(7)

def pnoise(shape):
    """频域生成 → 天然以 T 为周期，循环处没有接缝"""
    nf = N // 2 + 1
    f = np.fft.rfftfreq(N, 1.0 / SR)
    mag = shape(f)
    spec = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, nf))
    spec[0] = 0.0
    x = np.fft.irfft(spec, n=N)
    return x / (np.abs(x).max() + 1e-12)

def lfo(period, phase=0.0):
    return np.sin(2 * np.pi * t / period + phase)

# --- 1. 低频底噪：身体的环境音 ---
drone = np.zeros(N)
for f0, amp in [(44.0, 1.0), (44.08, 0.8), (66.0, 0.45), (88.0, 0.22), (132.0, 0.09)]:
    slow = 0.75 + 0.25 * lfo(25.0, f0)
    drone += amp * slow * np.sin(2 * np.pi * f0 * t)
drone /= np.abs(drone).max()

# --- 2. 液体涌动：带通噪声，缓慢起伏 ---
wash = pnoise(lambda f: np.exp(-((np.log((f + 1e-6) / 220.0)) ** 2) / 1.1) / (1 + (f / 2600.0) ** 2))
swell = 0.30 + 0.70 * (0.5 + 0.5 * lfo(25.0)) * (0.6 + 0.4 * (0.5 + 0.5 * lfo(12.5, 1.1)))
wash *= swell

# --- 3. 远处的微光：很轻的高频，给空间感 ---
shim = pnoise(lambda f: np.exp(-((np.log((f + 1e-6) / 3000.0)) ** 2) / 0.5))
shim *= 0.25 + 0.75 * (0.5 + 0.5 * lfo(50.0, 2.0))

# --- 4. 心跳：lub-dub ---
heart = np.zeros(N)
def thump(start, amp, tau, f_hi, f_lo, dur=0.45):
    n = int(dur * SR)
    i0 = int(round(start * SR)) % N
    k = np.arange(n) / SR
    env = np.exp(-k / tau)
    f = f_lo + (f_hi - f_lo) * np.exp(-k / 0.055)      # 音高快速下滑 → "咚"
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * env
    # 1 ms 淡入：噪声首样本是随机值，不淡入会在循环接缝留下咔哒声
    fade = np.clip(k / 0.001, 0.0, 1.0)
    thud = pnoise_short(n) * np.exp(-k / 0.013) * 0.42 * fade  # 一点点冲击质感
    seg = amp * (body + thud)
    idx = (i0 + np.arange(n)) % N
    np.add.at(heart, idx, seg)

def pnoise_short(n):
    x = rng.normal(0, 1, n)
    # 简单低通，别太刺
    b = np.ones(24) / 24.0
    return np.convolve(x, b, mode="same")

for i in range(int(round(T / beat))):
    s = i * beat
    breathe = 0.85 + 0.15 * np.sin(2 * np.pi * s / 25.0)   # 强弱有起伏，不机械
    thump(s, 1.00 * breathe, 0.058, 68.0, 36.0)            # lub
    thump(s + 0.32 * beat, 0.50 * breathe, 0.044, 56.0, 33.0)  # dub
heart /= np.abs(heart).max()

# --- 混音 ---
mix = 0.24 * drone + 0.19 * wash + 0.035 * shim + 0.85 * heart

# 轻微高通，去掉听不见但占动态的超低频
sp = np.fft.rfft(mix)
f = np.fft.rfftfreq(N, 1.0 / SR)
sp *= 1.0 / (1.0 + (28.0 / np.maximum(f, 1e-6)) ** 4)
mix = np.fft.irfft(sp, n=N)

mix = np.tanh(mix * 1.15) / np.tanh(1.15)        # 软限幅
mix *= 0.72 / (np.abs(mix).max() + 1e-12)        # 留头
rms = np.sqrt((mix ** 2).mean())
print(f"长度 {T:.1f}s  峰值 {np.abs(mix).max():.3f}  RMS {20*np.log10(rms):.1f} dBFS")

stereo = np.stack([mix, np.roll(mix, int(0.004 * SR))], axis=1)  # 极轻微展宽
stereo *= 0.72 / (np.abs(stereo).max() + 1e-12)
np.save("mix.npy", stereo.astype(np.float32))
