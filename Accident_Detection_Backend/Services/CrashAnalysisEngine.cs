using System;
using System.Collections.Generic;
using System.Linq;
using AccidentDetectionAndAlertSystem.Configuration;
using Accident_Detection_Backend.Models;

namespace AccidentDetectionAndAlertSystem.Services
{
    public class CrashAnalysisResult
    {
        public bool IsCrash { get; set; }
        public string FilterReason { get; set; } = string.Empty;
        public double GForce { get; set; }
        public double ToyMassKg { get; set; }
        public double ToyForceNewtons { get; set; }
        public double RealWorldForceNewtons { get; set; }
        public double VehicleMassKg { get; set; }
        public double LengthScaleFactor { get; set; }
        public double ForceScaleRatio { get; set; }
        public double BaselineReferenceMassKg { get; set; }

        public string ImpactSide { get; set; } = "Front";
        public string AccidentType { get; set; } = "Impact";
        public string SteeringSide { get; set; } = "Right-Hand";
        public bool IsRollover { get; set; }

        public int StartNode { get; set; }
        public double CabinForce { get; set; }
        public double CabinDamagePercent { get; set; }
        public double DeadEndTransferForce { get; set; }

        public Dictionary<int, double> NodeForces { get; set; } = new();
        public Dictionary<int, double> DeadEndForces { get; set; } = new();

        // Biomechanical Occupant Severity
        public double PassengerForce { get; set; }
        public double PassengerG { get; set; }
        public string PassengerAIS { get; set; } = "AIS 0";
        public string PassengerSeverity { get; set; } = "None";
        public string PassengerInjury { get; set; } = string.Empty;

        public double DriverForce { get; set; }
        public double DriverG { get; set; }
        public string DriverAIS { get; set; } = "AIS 0";
        public string DriverSeverity { get; set; } = "None";
        public string DriverInjury { get; set; } = string.Empty;

        public string OccupantSummary { get; set; } = string.Empty;
    }

    public class CrashAnalysisEngine
    {
        private readonly CrashScalingConfig _config;

        public CrashAnalysisEngine(CrashScalingConfig config)
        {
            _config = config ?? new CrashScalingConfig();
        }

        /// <summary>
        /// Dynamically resolves the full-scale vehicle mass in KG based on registered DB Category,
        /// vehicle make, or request override. Matches benchmark vehicle profiles (Hatchback_Alto, Sedan_Civic, SUV_Prado).
        /// </summary>
        public double ResolveVehicleMassKg(Category? category, Car? car, AccidentRequest request)
        {
            if (request.VehicleMassKg.HasValue && request.VehicleMassKg.Value > 0)
                return request.VehicleMassKg.Value;

            if (category?.Weight.HasValue == true && category.Weight.Value > 0)
            {
                double w = Convert.ToDouble(category.Weight.Value);
                // If entered in metric tons (< 50) convert to kg; otherwise use raw kg
                return w > 50.0 ? w : w * 1000.0;
            }

            string catName = (category?.Name ?? "").ToLowerInvariant();
            string carMake = (car?.Make ?? "").ToLowerInvariant();
            int catId = car?.Category_Id ?? category?.Category_Id ?? 1;

            if (catName.Contains("alto") || catName.Contains("hatchback") || carMake.Contains("alto") || catId == 3)
            {
                return _config.CategoryWeightsKg.TryGetValue("Hatchback_Alto", out var mass) ? mass : 850.0;
            }
            if (catName.Contains("prado") || catName.Contains("suv") || carMake.Contains("prado") || catId == 2)
            {
                return _config.CategoryWeightsKg.TryGetValue("SUV_Prado", out var mass) ? mass : 2150.0;
            }

            // Default: Sedan_Civic benchmark
            return _config.CategoryWeightsKg.TryGetValue("Sedan_Civic", out var defMass) ? defMass : _config.BaselineReferenceMassKg;
        }

        /// <summary>
        /// Derives scalar G-force magnitude from direct G-force telemetry or linear acceleration vectors.
        /// </summary>
        public double DeriveGForce(AccidentRequest request)
        {
            if (request.GForce.HasValue && request.GForce.Value > 0)
                return request.GForce.Value;

            if (request.Acceleration > 0)
            {
                // CoreMotion / test rigs sending m/s^2 (e.g. > 25 m/s^2) vs direct G-units
                return request.Acceleration >= 25.0 ? request.Acceleration / 9.81 : request.Acceleration;
            }

            double vectorMag = Math.Sqrt(request.AccelX * request.AccelX + request.AccelY * request.AccelY + request.AccelZ * request.AccelZ);
            if (vectorMag > 0)
            {
                return vectorMag >= 25.0 ? vectorMag / 9.81 : vectorMag;
            }

            return 0.0;
        }

        /// <summary>
        /// Evaluates incoming IMU telemetry against pure edge-case filters (phone drops, speed breakers, hard brakes, drifts)
        /// and applies Froude Similitude scaling law, BFS graph propagation, and occupant AIS injury calculations.
        /// </summary>
        public CrashAnalysisResult Analyze(
            AccidentRequest request,
            Car? car,
            Category? category,
            List<Nodes> nodeEntities,
            List<NodeConnection> connectionEntities)
        {
            double gForce = DeriveGForce(request);
            double vehicleMassKg = ResolveVehicleMassKg(category, car, request);
            double toyMassKg = request.ToyMassKg.HasValue && request.ToyMassKg.Value > 0
                ? request.ToyMassKg.Value
                : _config.ToyMassKg;

            var result = new CrashAnalysisResult
            {
                GForce = gForce,
                ToyMassKg = toyMassKg,
                VehicleMassKg = vehicleMassKg,
                LengthScaleFactor = _config.LengthScaleFactor,
                ForceScaleRatio = _config.ForceScale,
                BaselineReferenceMassKg = _config.BaselineReferenceMassKg
            };

            // ================= 1. PURE IMU EDGE-CASE FILTERS =================

            // Filter A: Phone Drop / Transient Impact Duration (< 15-30 ms)
            if (request.ImpactDurationMs.HasValue && request.ImpactDurationMs.Value < _config.MinimumImpactDurationMs)
            {
                result.IsCrash = false;
                result.FilterReason = $"Phone Drop: Transient impact duration ({request.ImpactDurationMs.Value:F1}ms < {_config.MinimumImpactDurationMs:F0}ms).";
                return result;
            }

            // Filter B: Speed Breaker / Road Hump (High pitch/vertical rotation with low linear deceleration)
            double gz = Math.Abs(request.GyroZ);
            if ((gz >= _config.SpeedBreakerGyroZThreshold || Math.Abs(request.AccelZ) > 3.0) && gForce < _config.SpeedBreakerGForceMax)
            {
                result.IsCrash = false;
                result.FilterReason = "Speed Breaker: Road hump pitch/yaw rotation without collision deceleration.";
                return result;
            }

            // Filter C: Hard Braking (< 1.1G - 1.2G ABS stop)
            if (gForce < _config.HardBrakingMaxGForce)
            {
                result.IsCrash = false;
                result.FilterReason = $"Hard Braking: Measured deceleration ({gForce:F2}G) is within normal ABS stopping limits (<{_config.HardBrakingMaxGForce:F1}G).";
                return result;
            }

            // Filter D: Aggressive Cornering / Drift (< 0.8G lateral)
            if (Math.Abs(request.AccelX) > 0.4 && gForce < _config.DriftMaxGForce)
            {
                result.IsCrash = false;
                result.FilterReason = $"Aggressive Cornering / Drift: Lateral force ({gForce:F2}G) is within non-collision vehicle dynamics.";
                return result;
            }

            // Filter E: Minimum Crash G-Force Threshold (< 4.0G)
            if (gForce < _config.MinimumCrashGForce)
            {
                result.IsCrash = false;
                result.FilterReason = $"Impact Below Crash Threshold: Measured {gForce:F2}G is below mandatory collision threshold ({_config.MinimumCrashGForce:F1}G).";
                return result;
            }

            // ================= 2. FROUDE SIMILITUDE CRASH SCALING =================
            // F_Toy = m_Toy * (G * 9.81)
            // F_Real = (F_Toy / S_L^3) * (M_DB / M_Ref)
            double toyForceNewtons = toyMassKg * (gForce * 9.81);
            double realWorldForceNewtons = _config.ToRealWorldForce(toyForceNewtons, vehicleMassKg);

            result.IsCrash = true;
            result.ToyForceNewtons = toyForceNewtons;
            result.RealWorldForceNewtons = realWorldForceNewtons;

            // ================= 3. IMPACT SIDE & ACCIDENT TYPE RESOLUTION =================
            string impactSide = ResolveImpactSide(request);
            result.ImpactSide = impactSide;

            double totalGyroMag = Math.Sqrt(request.GyroX * request.GyroX + request.GyroY * request.GyroY + request.GyroZ * request.GyroZ);
            bool isRollover = impactSide.Equals("Rollover", StringComparison.OrdinalIgnoreCase) || totalGyroMag >= _config.RolloverGyroMagnitudeThreshold;
            result.IsRollover = isRollover;

            if (isRollover)
            {
                result.AccidentType = "Rollover";
                result.ImpactSide = "Rollover";
            }
            else if (impactSide.Contains("Front", StringComparison.OrdinalIgnoreCase))
            {
                result.AccidentType = "Frontal Collision";
            }
            else if (impactSide.Contains("Rear", StringComparison.OrdinalIgnoreCase))
            {
                result.AccidentType = "Rear Collision";
            }
            else
            {
                result.AccidentType = "Side Impact";
            }

            // Determine steering side (Right-Hand vs Left-Hand)
            string steeringSide = !string.IsNullOrWhiteSpace(request.SteeringSide)
                ? request.SteeringSide.Trim()
                : (!string.IsNullOrWhiteSpace(car?.Steering_Side)
                    ? car.Steering_Side.Trim()
                    : "Right-Hand");
            result.SteeringSide = steeringSide;

            // ================= 4. BFS GRAPH IMPACT PROPAGATION =================
            int categoryId = car?.Category_Id ?? category?.Category_Id ?? 1;
            int startNode = ResolveStartNode(nodeEntities, categoryId, result.ImpactSide);
            result.StartNode = startNode;

            var absorption = nodeEntities.ToDictionary(n => n.Node_Id, n => (double)(n.Force ?? 0.0m));
            var (nodeForces, deadEndForces) = PropagateForce(connectionEntities, absorption, startNode, realWorldForceNewtons, isRollover);

            result.NodeForces = nodeForces;
            result.DeadEndForces = deadEndForces;

            double totalDeadEndForce = deadEndForces.Values.Sum();
            result.DeadEndTransferForce = totalDeadEndForce;

            double cabinForce;
            if (!isRollover && totalDeadEndForce > 0)
            {
                cabinForce = totalDeadEndForce;
            }
            else
            {
                cabinForce = nodeForces.ContainsKey(13)
                    ? nodeForces[13]
                    : (nodeForces.Any() ? nodeForces.Values.Max() * 0.35 : realWorldForceNewtons * 0.25);
            }

            if (isRollover)
            {
                cabinForce *= _config.RolloverForceMultiplier;
            }
            result.CabinForce = cabinForce;

            // Cabin damage percentage (power curve 1.6)
            double maxForce = Math.Max(realWorldForceNewtons, nodeForces.Values.DefaultIfEmpty(realWorldForceNewtons).Max());
            if (maxForce <= 0) maxForce = 1;

            double normalized = Math.Min(1.0, cabinForce / maxForce);
            double damage = Math.Pow(normalized, 1.6) * 100.0;
            if (isRollover) damage *= _config.RolloverDamageMultiplier;
            damage = Math.Max(1.0, Math.Min(100.0, damage));
            result.CabinDamagePercent = damage;

            // ================= 5. OCCUPANT INJURY SEVERITY (AIS SCORES) =================
            EvaluateOccupantInjuries(result, gForce, cabinForce, result.ImpactSide, steeringSide, isRollover);

            return result;
        }

        private (Dictionary<int, double> nodeForces, Dictionary<int, double> deadEndForces) PropagateForce(
            List<NodeConnection> connections,
            Dictionary<int, double> absorption,
            int startNode,
            double initialForce,
            bool isRollover)
        {
            var visited = new HashSet<int>();
            var nodeForces = new Dictionary<int, double>();
            var deadEndForces = new Dictionary<int, double>();

            var graph = connections.GroupBy(c => c.From_Node).ToDictionary(g => g.Key, g => g.ToList());
            var queue = new Queue<(int node, double force)>();

            queue.Enqueue((startNode, initialForce));

            while (queue.Count > 0)
            {
                var (node, incoming) = queue.Dequeue();
                if (visited.Contains(node)) continue;
                visited.Add(node);

                nodeForces[node] = incoming;
                double absorb = absorption.TryGetValue(node, out var absVal) ? absVal : 0;
                double remaining = Math.Max(0, (incoming - absorb) * _config.EnergyAttenuationFactor);

                if (remaining <= 5) continue;
                if (!graph.ContainsKey(node)) continue;

                var outbound = graph[node];
                if (outbound == null || outbound.Count == 0) continue;

                foreach (var edge in outbound)
                {
                    if (!isRollover && edge.Is_Cabin_Deadend)
                    {
                        if (!deadEndForces.ContainsKey(node)) deadEndForces[node] = 0;
                        deadEndForces[node] += remaining;
                    }
                    else if (edge.To_Node != node && !visited.Contains(edge.To_Node))
                    {
                        double weight = (edge.Force_Weight.HasValue && edge.Force_Weight.Value > 0)
                            ? (double)edge.Force_Weight.Value
                            : (1.0 / outbound.Count);

                        queue.Enqueue((edge.To_Node, remaining * weight));
                    }
                }
            }

            return (nodeForces, deadEndForces);
        }

        private void EvaluateOccupantInjuries(
            CrashAnalysisResult result,
            double gForce,
            double cabinForce,
            string impactSide,
            string steeringSide,
            bool isRollover)
        {
            bool isRHD = !steeringSide.Equals("Left-Hand", StringComparison.OrdinalIgnoreCase) &&
                         !steeringSide.Equals("Left", StringComparison.OrdinalIgnoreCase) &&
                         !steeringSide.Equals("LHD", StringComparison.OrdinalIgnoreCase);

            double baseOccupantForce = Math.Max(cabinForce * 0.40, (gForce * 9.81) * 70.0);
            double baseOccupantG = baseOccupantForce / (70.0 * 9.81);

            double passengerMultiplier = 1.0;
            double driverMultiplier = 1.0;
            string summary;

            if (isRollover)
            {
                passengerMultiplier = _config.RolloverForceMultiplier;
                driverMultiplier = _config.RolloverForceMultiplier;
                summary = "Rollover Hazard: Severe multi-axis roof crush danger for all occupants.";
            }
            else if (impactSide.Contains("Right", StringComparison.OrdinalIgnoreCase))
            {
                if (isRHD)
                {
                    driverMultiplier = _config.DirectImpactMultiplier;
                    passengerMultiplier = _config.FarSideBufferMultiplier;
                    summary = "RHD Vehicle: Driver in direct right-side impact zone. Passenger on Left has lateral crumple buffer.";
                }
                else
                {
                    passengerMultiplier = _config.DirectImpactMultiplier;
                    driverMultiplier = _config.FarSideBufferMultiplier;
                    summary = "LHD Vehicle: Passenger in direct right-side impact zone! High passenger intrusion risk.";
                }
            }
            else if (impactSide.Contains("Left", StringComparison.OrdinalIgnoreCase))
            {
                if (isRHD)
                {
                    passengerMultiplier = _config.DirectImpactMultiplier;
                    driverMultiplier = _config.FarSideBufferMultiplier;
                    summary = "RHD Vehicle: Passenger in direct left-side impact zone! High passenger intrusion risk.";
                }
                else
                {
                    driverMultiplier = _config.DirectImpactMultiplier;
                    passengerMultiplier = _config.FarSideBufferMultiplier;
                    summary = "LHD Vehicle: Driver in direct left-side impact zone. Passenger on Right has lateral crumple buffer.";
                }
            }
            else if (impactSide.Contains("Front", StringComparison.OrdinalIgnoreCase))
            {
                passengerMultiplier = 1.0;
                driverMultiplier = 1.0;
                summary = "Frontal Impact: Symmetric forward deceleration, seatbelt & airbag engagement.";
            }
            else if (impactSide.Contains("Rear", StringComparison.OrdinalIgnoreCase))
            {
                passengerMultiplier = 0.9;
                driverMultiplier = 0.9;
                summary = "Rear Collision: Rearward seatback rebound and whiplash on occupants.";
            }
            else
            {
                summary = "General structural vehicle collision.";
            }

            double passengerForce = baseOccupantForce * passengerMultiplier;
            double passengerG = baseOccupantG * passengerMultiplier;
            var (pAis, pSev, pInj) = MapInjuryAIS(passengerForce, passengerG);

            double driverForce = baseOccupantForce * driverMultiplier;
            double driverG = baseOccupantG * driverMultiplier;
            var (dAis, dSev, dInj) = MapInjuryAIS(driverForce, driverG);

            result.PassengerForce = passengerForce;
            result.PassengerG = passengerG;
            result.PassengerAIS = pAis;
            result.PassengerSeverity = pSev;
            result.PassengerInjury = pInj;

            result.DriverForce = driverForce;
            result.DriverG = driverG;
            result.DriverAIS = dAis;
            result.DriverSeverity = dSev;
            result.DriverInjury = dInj;
            result.OccupantSummary = summary;
        }

        private static (string ais, string severity, string injury) MapInjuryAIS(double forceN, double g)
        {
            if (g >= 40.0 || forceN >= 27440)
            {
                return ("AIS 5-6", "Critical / Fatal", "Critical / Fatal: High probability of life-threatening organ rupture, severe spinal injury, or death.");
            }
            if (g >= 20.0 || forceN >= 13720)
            {
                return ("AIS 3-4", "Serious to Severe", "Serious to Severe: Structural cabin intrusion. High risk of rib fractures, severe traumatic brain injury (TBI), or internal bleeding.");
            }
            if (g >= 10.0 || forceN >= 6860)
            {
                return ("AIS 2", "Moderate", "Moderate: Airbag deployment threshold (~10-15G). Seatbelt bruising, minor concussions, chest contusions, wrist/collarbone fractures.");
            }
            if (g >= 4.0 || forceN >= 2744)
            {
                return ("AIS 1", "Minor", "Minor: Mild neck strain/whiplash, minor soft tissue pain, superficial bruising.");
            }
            return ("AIS 0", "None", "None: Normal driving baseline / no injury.");
        }

        private static string ResolveImpactSide(AccidentRequest request)
        {
            if (!string.IsNullOrWhiteSpace(request.ImpactSide) &&
                !request.ImpactSide.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
                !request.ImpactSide.Equals("Minor", StringComparison.OrdinalIgnoreCase) &&
                !request.ImpactSide.Equals("None", StringComparison.OrdinalIgnoreCase) &&
                !request.ImpactSide.Equals("-", StringComparison.OrdinalIgnoreCase))
            {
                return request.ImpactSide.Trim();
            }

            double lr = request.AccelX;
            double fb = request.AccelY;

            if (lr == 0 && fb == 0 && (request.GyroX != 0 || request.GyroY != 0))
            {
                lr = request.GyroX;
                fb = request.GyroY;
            }

            double absLR = Math.Abs(lr);
            double absFB = Math.Abs(fb);

            if (absLR < 0.1 && absFB < 0.1) return "Front";

            double ratio = absLR / Math.Max(absFB, 0.0001);
            if (absLR >= 0.2 && absFB >= 0.2 && ratio >= 0.45 && ratio <= 2.2)
            {
                string longitudinal = fb >= 0 ? "Front" : "Rear";
                string lateral = lr >= 0 ? "Right" : "Left";
                return $"{longitudinal}-{lateral}";
            }

            if (absFB >= absLR) return fb >= 0 ? "Front" : "Rear";
            return lr >= 0 ? "Right" : "Left";
        }

        public static int ResolveStartNode(List<Nodes> nodes, int categoryId, string impactSide)
        {
            string side = (impactSide ?? "").Trim().ToLower();

            var exact = nodes.FirstOrDefault(n => (n.Node_Position ?? "").Trim().ToLower() == side);
            if (exact != null) return exact.Node_Id;

            if (nodes.Any())
            {
                Nodes? matched = null;
                if (side == "front")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("front") &&
                                                       ((n.Node_Position ?? "").ToLower().Contains("center") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("grille") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("bumper")))
                              ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("front"));
                }
                else if (side == "front-left")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("front") && (n.Node_Position ?? "").ToLower().Contains("left"));
                }
                else if (side == "front-right")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("front") && (n.Node_Position ?? "").ToLower().Contains("right"));
                }
                else if (side == "rear")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("rear") &&
                                                       ((n.Node_Position ?? "").ToLower().Contains("center") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("bumper") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("end") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("trunk")))
                              ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("rear"));
                }
                else if (side == "rear-left")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("rear") && (n.Node_Position ?? "").ToLower().Contains("left"));
                }
                else if (side == "rear-right")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("rear") && (n.Node_Position ?? "").ToLower().Contains("right"));
                }
                else if (side == "left")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("left") &&
                                                       ((n.Node_Position ?? "").ToLower().Contains("door") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("pillar") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("side")))
                              ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("left"));
                }
                else if (side == "right")
                {
                    matched = nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("right") &&
                                                       ((n.Node_Position ?? "").ToLower().Contains("door") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("pillar") ||
                                                        (n.Node_Position ?? "").ToLower().Contains("side")))
                              ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("right"));
                }

                if (matched != null) return matched.Node_Id;
            }

            // Category Blueprint Fallbacks
            if (categoryId == 2) // SUV
            {
                return side switch
                {
                    "front" => 1,
                    "front-left" => 3,
                    "front-right" => 2,
                    "left" => 10,
                    "right" => 13,
                    "rear" => 24,
                    "rear-left" => 23,
                    "rear-right" => 25,
                    _ => 1
                };
            }
            if (categoryId == 3) // Hatchback
            {
                return side switch
                {
                    "front" => 1,
                    "front-left" => 2,
                    "front-right" => 3,
                    "left" => 16,
                    "right" => 17,
                    "rear" => 23,
                    "rear-left" => 21,
                    "rear-right" => 22,
                    _ => 1
                };
            }

            // Sedan (Category 1 / Default)
            return side switch
            {
                "front" => 1,
                "front-left" => 2,
                "front-right" => 3,
                "left" => 15,
                "right" => 17,
                "rear" => 30,
                "rear-left" => 28,
                "rear-right" => 29,
                _ => 1
            };
        }
    }
}
