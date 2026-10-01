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
            // 1. Filter low G-force events (Hard brakes / light handling)
            if (gForceMagnitude < _config.MinimumCrashGForce)
            {
                return false;
            }

            // 2. CRITICAL FILTER: Ignore brief phone taps / finger flicks (<35ms)
            // Real structural car crashes deform over 50ms - 150ms.
            if (impactDurationMs > 0 && impactDurationMs < _config.MinimumImpactDurationMs)
            {
                return false; 
            }

            return true; // Confirmed valid impact event
        }
    }
}
