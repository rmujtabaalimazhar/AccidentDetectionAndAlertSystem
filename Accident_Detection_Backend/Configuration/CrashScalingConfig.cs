using System;
using System.Collections.Generic;

namespace AccidentDetectionAndAlertSystem.Configuration
{
    public class CrashScalingConfig
    {
        // 1:25 physical toy car parameters (Froude Similitude)
        public double LengthScaleFactor { get; set; } = 0.04; // 1:25 Toy scale (1.0 for real vehicle)
        public double BaselineReferenceMassKg { get; set; } = 1500.0; // Universal anchor benchmark (Sedan_Civic reference)
        public double ToyMassKg { get; set; } = 0.096; // 96 grams toy car testing rig mass

        // Pure IMU Edge-case Filters
        public double MinimumCrashGForce { get; set; } = 4.0; // Filters hard brakes (<1.1G) & drifts (<0.6G)
        public double MinimumImpactDurationMs { get; set; } = 30.0; // Filters phone drops (<15ms)
        public double HardBrakingMaxGForce { get; set; } = 1.2; // Maximum deceleration possible from dry asphalt ABS braking
        public double DriftMaxGForce { get; set; } = 0.8; // Maximum lateral acceleration from aggressive drifting / turning
        public double SpeedBreakerGyroZThreshold { get; set; } = 3.0; // Angular velocity spike for road humps
        public double SpeedBreakerGForceMax { get; set; } = 3.5; // Max G-force during speed bump traversal
        public double RolloverGyroMagnitudeThreshold { get; set; } = 12.0; // Gyroscope rad/s threshold for multi-axis vehicle tumble

        // Structural Propagation & Biomechanical Injury Multipliers
        public double EnergyAttenuationFactor { get; set; } = 0.65; // Chassis deformation energy absorption per node hop
        public double RolloverForceMultiplier { get; set; } = 1.45; // Cabin force amplification under roof crush
        public double RolloverDamageMultiplier { get; set; } = 1.35; // Structural intrusion damage multiplier in rollovers
        public double DirectImpactMultiplier { get; set; } = 1.25; // Direct occupant impact side amplification
        public double FarSideBufferMultiplier { get; set; } = 0.55; // Far occupant lateral buffer reduction

        // Default category vehicle masses in KG (if not specified in DB Category.Weight)
        public Dictionary<string, double> CategoryWeightsKg { get; set; } = new(StringComparer.OrdinalIgnoreCase)
        {
            { "Hatchback_Alto", 850.0 },
            { "Sedan_Civic", 1500.0 },
            { "SUV_Prado", 2150.0 },
            { "Hatchback", 850.0 },
            { "Sedan", 1500.0 },
            { "SUV", 2150.0 }
        };

        // Froude Derived Scaling Factors
        public double ForceScale => Math.Pow(LengthScaleFactor, 3); // (0.04)^3 = 0.000064

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
            return CalculateRealForceFromGForce(gForceMagnitude, ToyMassKg, dbVehicleMassKg);
        }
    }
}

namespace Accident_Detection_Backend.Configuration
{
    // Alias wrapper for project namespace consistency
    public class CrashScalingConfig : AccidentDetectionAndAlertSystem.Configuration.CrashScalingConfig
    {
    }
}
