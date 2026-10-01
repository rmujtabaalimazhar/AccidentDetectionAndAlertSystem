using System;
using AccidentDetectionAndAlertSystem.Configuration;

namespace AccidentDetectionAndAlertSystem.Services
{
    public class CrashFilterEngine
    {
        private readonly CrashScalingConfig _config;

        public CrashFilterEngine(CrashScalingConfig config)
        {
            _config = config ?? new CrashScalingConfig();
        }

        public bool IsValidCrash(double gForceMagnitude, double impactDurationMs)
        {
            // Filter 1: Magnitude cutoff (hard brakes / drifting < 4.5G)
            if (gForceMagnitude < _config.MinimumCrashGForce)
                return false;

            // Filter 2: Duration cutoff (phone taps / finger flicks < 35ms)
            if (impactDurationMs < _config.MinimumImpactDurationMs)
                return false;

            return true; // Valid structural collision
        }
    }
}
