# Empirical Sensor Calibration Datasets & Classification Stack
### Accident Detection & Alert System (FYP)

This repository includes real-world empirical trial datasets recorded directly with the iOS application's **Real-Time Dataset Recorder** on physical test hardware, alongside their mathematical analysis, calibrated thresholds, and prioritized classification stack.

---

## 1. Summary of Recorded Datasets

| Dataset File | Scenario | Sample Count | Duration | Peak Gyroscope | Peak Linear Accel | Gravity Vector Inversion ($g_z$) |
|---|---|---|---|---|---|---|
| **`Trial_1_-_Free_Fall_Drop_(1m).json`** | Free-Fall Phone Drop (1 Meter) | 1,481 frames | ~29.7 sec | 1.83 rad/s | 235.8 m/s² (24.0 G) | None ($g_z \approx -0.99$ to random) |
| **`Trial_1_-_Lateral_Rollover_(360°).csv`** | Lateral Rollover Flips (360° Rolls) | 3,040 frames | 61.1 sec | 35.39 rad/s (2,028°/s) | 39.7 m/s² (4.04 G) | Complete: $-1.00 \to +1.00$ (Inverted Roof) |

---

## 2. Priority Classification Stack ("Stacked Without Mixing Up")

To eliminate false triggers between **Palm Hits / Linear Shocks**, **Rollovers**, and **Phone Drops**, the system executes a 3-layer deterministic decision stack:

```
                            [ SENSOR INPUT (50Hz Accelerometer, Gyroscope & Attitude) ]
                                                        |
                                                        v
                                +-----------------------------------------------+
                                |  LAYER 1: ROLLOVER DETECTION (ROTATION > 90°) |
                                +-----------------------------------------------+
                                  * Condition: Device Attitude Roll or Pitch > 90° (|roll| > π/2 or |pitch| > π/2)
                                               OR Roof Inversion (g_z > +0.15G) with active angular roll (≥ 2.0 rad/s)
                                  * Palm Hit Rejection: A palm strike changes tilt by < 20° and NEVER exceeds 90°.
                                         |                                |
                                     [ YES ]                           [ NO ]
                                         |                                |
                                         v                                v
                             >>> ROLLOVER ACCIDENT <<<        +-----------------------------------------+
                             - 1.45x Roof Crush Multiplier    |  LAYER 2: PHONE FREE-FALL (≥ 1.75 FEET) |
                             - Cabin Intrusion Alert          +-----------------------------------------+
                                                                * Condition: Continuous near zero-G (< 0.42G)
                                                                             for AT LEAST 120 ms (measured 1.75ft IMU window)
                                                                * Immediate Landing Trigger: On floor impact shock,
                                                                  triggers immediately without bounce cancellation.
                                                                * Palm Hit Rejection: Hand flicks or slaps last < 50ms (0ms in CSV).
                                                                       |                                |
                                                                   [ YES ]                           [ NO ]
                                                                       |                                |
                                                                       v                                v
                                                           >>> PHONE FALL (SAFE) <<<         +-------------------------------------+
                                                           - 0% Structural Damage            |  LAYER 3: LINEAR IMPACT & HIT SIDES |
                                                           - SMS / Call Suppressed           +-------------------------------------+
                                                                                               * Condition: Peak impact shock vector
                                                                                                            sampled at compression peak
                                                                                               * Physical Deceleration Signs:
                                                                                                 - Front Hit: dynY ≤ 0 (Rearward decel)
                                                                                                 - Rear Hit:  dynY > 0 (Forward accel)
                                                                                                 - Right Hit: dynX ≤ 0 (Leftward decel)
                                                                                                 - Left Hit:  dynX > 0 (Rightward accel)
```

---

## 3. Physical Calibration Details

### A. Fall Height Gating ($\ge 1.75\text{ Feet}$)
From the empirical 1-meter trial recordings:
- In real-world handheld drops, human release friction and IMU low-pass filtering produce a measured zero-G duration ($totalMagG < 0.42$) between **120 ms and 280 ms** (mean: 212.7 ms).
- **Calibrated Threshold:** `MinimumFreeFallDurationMs = 120.0 ms`.
- **Immediate Landing Trigger:** Because phone drops produce an instant transient bounce shock ($< 35\text{ ms}$), the moment floor contact occurs ($linearAcc \ge 14.7\text{ m/s}^2$) following a verified airborne free-fall, the system triggers the Phone Fall edge case immediately.
- Any palm strike, table tap, or handling flick lasts $< 50\text{ ms}$ (verified 0 instances $\ge 60\text{ ms}$ in rollover dataset).

### B. Rollover Rotation Gating ($> 90^\circ$)
- Evaluates `CMAttitude`: `abs(roll) > 1.5708` ($90^\circ$) or `abs(pitch) > 1.5708` ($90^\circ$), or $g_z > 0.15\text{ G}$.
- Prevents 1-frame vibration spikes during palm hits from being mislabeled as rollovers.

### C. True Peak Impact Vector Capture (Palm Hit Testing)
- Samples the **peak impact shock** ($\max \sqrt{u_x^2 + u_y^2 + u_z^2}$) during the high-force window.
- Eliminates sign flipping caused by post-impact mechanical rebounds and bounce oscillations.
