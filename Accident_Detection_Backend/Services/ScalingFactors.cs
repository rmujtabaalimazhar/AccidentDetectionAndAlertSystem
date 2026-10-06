using System;
using System.Collections.Generic;

namespace Accident_Detection_Backend.Services
{
    /// <summary>
    /// Centralized Scaling Factors and Physical Constants for the Accident Detection System.
    /// Defines Froude Similitude scale ratios, benchmark vehicle masses, sensor thresholds,
    /// and structural attenuation factors used across the backend.
    /// </summary>
    public class ScalingFactors
    {
        // ==========================================
        // 1. GEOMETRIC & FORCE SCALE RATIOS
        // ==========================================
        public double LengthScaleFactor { get; set; } = 0.10;          // 1:10 Geometric scale ratio (S_L = 0.10)
        public double BaselineReferenceMassKg { get; set; } = 1500.0; // Reference full-size sedan mass (Honda Civic benchmark)
        public double TestRigMassKg { get; set; } = 2.0;              // Mass of test model vehicle + sensor rig (kg)

        public double ToyMassKg
        {
            get => TestRigMassKg;
            set => TestRigMassKg = value;
        }

        // ==========================================
        // 2. CRASH & SENSOR THRESHOLDS
        // ==========================================
        public double MinimumCrashGForce { get; set; } = 2.0;         // Minimum linear acceleration (~19.6 m/s² pure shock)
        public double MinimumImpactDurationMs { get; set; } = 35.0;   // Minimum sustained impact window (filters brief taps <35ms)

        // ==========================================
        // 3. FALSE-ALARM EDGE-CASE CUTOFFS
        // ==========================================
        public double HardBrakingMaxGForce { get; set; } = 1.2;       // Maximum deceleration during ABS emergency braking (<1.2G)
        public double DriftMaxGForce { get; set; } = 0.8;             // Maximum lateral force during aggressive cornering / drift (<0.8G)
        public double SpeedBreakerGyroZThreshold { get; set; } = 3.0; // Pitch rotation rate over road speed humps
        public double SpeedBreakerGForceMax { get; set; } = 1.5;     // Maximum G-force expected over a road hump
        
        // Empirically Calibrated from Trial_1_-_Lateral_Rollover_(360°).csv:
        // Peak roll rate reached 35.39 rad/s; sustained roll bursts maintained 8.3 - 35.4 rad/s.
        public double RolloverGyroMagnitudeThreshold { get; set; } = 4.5;  // Sustained angular velocity threshold (rad/s) for rollover classification
        public double RolloverRoofInversionGravityZ { get; set; } = 0.50;  // Upright gravity is -1.0; inverted roof contact is +0.50 to +1.00

        // Phone Fall Edge-Case Height Calibration (At least 1 foot: measured sensor zero-G >= 50ms)
        public double MinimumFallHeightFeet { get; set; } = 1.0;
        public double MinimumFreeFallDurationMs { get; set; } = 50.0; // Measured airborne weightless duration (ms) for >= 1 ft drop qualification

        // ==========================================
        // 4. STRUCTURAL & BIOMECHANICAL MULTIPLIERS
        // ==========================================
        public double EnergyAttenuationFactor { get; set; } = 0.65;   // Chassis structural damping factor per node (65% absorbed)
        public double RolloverForceMultiplier { get; set; } = 1.45;   // Force multiplier for roof crush impact
        public double RolloverDamageMultiplier { get; set; } = 1.35;  // Multiplier for rollover cabin damage %
        public double DirectImpactMultiplier { get; set; } = 1.25;    // Direct T-bone impact side occupant penalty (1.25x)
        public double FarSideBufferMultiplier { get; set; } = 0.55;   // Far-side occupant protection buffer (0.55x)

        // ==========================================
        // 5. REGISTERED VEHICLE BENCHMARK WEIGHTS (KG)
        // ==========================================
        public Dictionary<string, double> CategoryWeightsKg { get; set; } = new(StringComparer.OrdinalIgnoreCase)
        {
            { "Hatchback_Alto", 850.0 },
            { "Sedan_Civic", 1500.0 },
            { "SUV_Prado", 2150.0 },
            { "Hatchback", 850.0 },
            { "Sedan", 1500.0 },
            { "SUV", 2150.0 }
        };

        // ==========================================
        // 6. SCALING MATHEMATICAL FORMULAS
        // ==========================================
        /// <summary>
        /// Volumetric force scale ratio: (LengthScaleFactor)^3 = (0.10)^3 = 0.001 (1:1000 force ratio)
        /// </summary>
        public double ForceScale => Math.Pow(LengthScaleFactor, 3);

        /// <summary>
        /// Scales test-rig force (Newtons) up to full-scale real vehicle collision force.
        /// Formula: F_Real = (F_Toy / ScaleRatio) * (M_Registered / M_Reference)
        /// </summary>
        public double ToRealWorldForce(double toyForceNewtons, double dbVehicleMassKg)
        {
            double baseRealForce = toyForceNewtons / ForceScale;
            double massRatio = dbVehicleMassKg / BaselineReferenceMassKg;
            return baseRealForce * massRatio;
        }

        /// <summary>
        /// Computes real-world force directly from G-force magnitude and registered vehicle mass.
        /// </summary>
        public double CalculateRealWorldForce(double gForceMagnitude, double databaseVehicleMassKg)
        {
            double testRigForceNewtons = TestRigMassKg * (gForceMagnitude * 9.81);
            return ToRealWorldForce(testRigForceNewtons, databaseVehicleMassKg);
        }

        /// <summary>
        /// Froude Kinematic Speed Scaling: Converts toy vehicle speed (m/s) to scaled full-size vehicle speed (km/h)
        /// Formula: v_base = v_toy / sqrt(0.10), v_real = v_base * sqrt(M_veh / 1500) * 3.6
        /// </summary>
        public static double CalculateRealWorldSpeedKmh(double toySpeedMs, double vehicleMassKg)
        {
            double speedScaleFactor = Math.Sqrt(0.10); // 0.3162277
            double baseRealSpeedMs = toySpeedMs / speedScaleFactor;
            double massFactor = Math.Sqrt(vehicleMassKg / 1500.0);
            double finalRealSpeedMs = baseRealSpeedMs * massFactor;
            return finalRealSpeedMs * 3.6; // Convert m/s to km/h
        }
    }

    /// <summary>
    /// Backward-compatible alias for legacy references
    /// </summary>
    public class CrashScalingConfig : ScalingFactors
    {
    }
}
