using System;
using System.Collections.Generic;

namespace AccidentDetectionAndAlertSystem.Configuration
{
    public class CrashScalingConfig
    {
        public double LengthScaleFactor { get; set; } = 0.10; // 1:10 scale (0.10)
        public double BaselineReferenceMassKg { get; set; } = 1500.0;
        public double TestRigMassKg { get; set; } = 2.0; // 2.0 kg larger test vehicle

        // Legacy / Alias compatibility for ToyMassKg
        public double ToyMassKg
        {
            get => TestRigMassKg;
            set => TestRigMassKg = value;
        }

        // Thresholds to eliminate tap false positives
        public double MinimumCrashGForce { get; set; } = 4.5;
        public double MinimumImpactDurationMs { get; set; } = 35.0; // Eliminates taps (<35ms)

        // Pure IMU edge-case filters
        public double HardBrakingMaxGForce { get; set; } = 1.2;
        public double DriftMaxGForce { get; set; } = 0.8;
        public double SpeedBreakerGyroZThreshold { get; set; } = 3.0;
        public double SpeedBreakerGForceMax { get; set; } = 3.5;
        public double RolloverGyroMagnitudeThreshold { get; set; } = 12.0;

        // Structural Propagation & Biomechanical Injury Multipliers
        public double EnergyAttenuationFactor { get; set; } = 0.65;
        public double RolloverForceMultiplier { get; set; } = 1.45;
        public double RolloverDamageMultiplier { get; set; } = 1.35;
        public double DirectImpactMultiplier { get; set; } = 1.25;
        public double FarSideBufferMultiplier { get; set; } = 0.55;

        // Default category vehicle masses in KG
        public Dictionary<string, double> CategoryWeightsKg { get; set; } = new(StringComparer.OrdinalIgnoreCase)
        {
            { "Hatchback_Alto", 850.0 },
            { "Sedan_Civic", 1500.0 },
            { "SUV_Prado", 2150.0 },
            { "Hatchback", 850.0 },
            { "Sedan", 1500.0 },
            { "SUV", 2150.0 }
        };

        // Derived Scale Factor (0.10)^3 = 0.001
        public double ForceScale => Math.Pow(LengthScaleFactor, 3);

        /// <summary>
        /// Calculates realistic real-world force for a larger 1:10 test car model
        /// </summary>
        public double CalculateRealWorldForce(double gForceMagnitude, double databaseVehicleMassKg)
        {
            // 1. Physical force on the 2.0 kg test vehicle
            double testRigForceNewtons = TestRigMassKg * (gForceMagnitude * 9.81);

            // 2. Scale up using 1:10 volume scale ratio (divide by 0.001)
            double baseRealForce = testRigForceNewtons / ForceScale;

            // 3. Adjust for specific registered vehicle mass (e.g. Alto = 800kg, Prado = 2200kg)
            double massRatio = databaseVehicleMassKg / BaselineReferenceMassKg;

            return baseRealForce * massRatio;
        }

        public double ToRealWorldForce(double toyForceNewtons, double dbVehicleMassKg)
        {
            double baseRealForce = toyForceNewtons / ForceScale;
            double massRatio = dbVehicleMassKg / BaselineReferenceMassKg;
            return baseRealForce * massRatio;
        }

        public double CalculateRealForceFromGForce(double gForceMagnitude, double toyMassKg, double dbVehicleMassKg)
        {
            double toyForceNewtons = toyMassKg * (gForceMagnitude * 9.81);
            return ToRealWorldForce(toyForceNewtons, dbVehicleMassKg);
        }

        public double CalculateRealForceFromGForce(double gForceMagnitude, double dbVehicleMassKg)
        {
            return CalculateRealWorldForce(gForceMagnitude, dbVehicleMassKg);
        }
    }
}

namespace Accident_Detection_Backend.Configuration
{
    public class CrashScalingConfig : AccidentDetectionAndAlertSystem.Configuration.CrashScalingConfig
    {
    }
}
