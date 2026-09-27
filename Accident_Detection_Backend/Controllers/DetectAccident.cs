/*
using Accident_Detection_Backend.Models;
using Accident_Detection_Backend.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace AccidentDetectionApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class DetectAccidentController : ControllerBase
    {
        private readonly AppDbContext db;
        private readonly PushNotificationService _pushService;

        public DetectAccidentController(AppDbContext context, PushNotificationService pushService)
        {
            db = context;
            _pushService = pushService;
        }

        [HttpPost("ImpactCalculation")]
        public async Task<IActionResult> ImpactCalculation([FromBody] AccidentRequest request)
        {
            try
            {
                if (request == null)
                    return BadRequest(new { status = "ERROR", message = "Invalid Request Body" });

                double acc = request.Acceleration;
                double gx = request.GyroX;
                double gy = request.GyroY;
                double gz = request.GyroZ;

                if (acc < 0.3)
                    return NoAccident("No Movement");

                var car = await db.Cars.FirstOrDefaultAsync(c => c.Car_Id == request.CarId);
                if (car == null)
                {
                    car = await db.Cars.FirstOrDefaultAsync();
                    if (car == null)
                        return NotFound(new { status = "ERROR", message = "Car not found" });
                }

                // Determine driving side (Right-Hand vs Left-Hand)
                string steeringSide = !string.IsNullOrWhiteSpace(request.SteeringSide)
                    ? request.SteeringSide.Trim()
                    : (!string.IsNullOrWhiteSpace(car.Steering_Side) ? car.Steering_Side.Trim() : "Right-Hand");

                var category = await db.Categories.FirstOrDefaultAsync(x => x.Category_Id == car.Category_Id);

                double weightTon = Convert.ToDouble(category?.Weight ?? 1.5m);
                if (weightTon <= 0) weightTon = 1.5;

                double mass = weightTon * 1000;

                // ================= PALM-HIT TEST FORCE AMPLIFICATION =================
                // When testing via palm strike on the device, acceleration is amplified by a constant multiplier
                // to realistically simulate multi-ton vehicle kinetic energy and structural collision forces.
                const double PALM_TEST_FORCE_MULTIPLIER = 3.5;
                double effectiveAcc = acc * PALM_TEST_FORCE_MULTIPLIER;
                double force = mass * effectiveAcc * 0.75;

                if (force < 200)
                    return NoAccident("Minor Vibration");

                if (Math.Abs(gz) > 3.0 && acc < 3.5)
                    return NoAccident("Speed Breaker");

                // ================= EXACT IMPACT SIDE DETECTION =================
                string impactSide;

                // 1. If caller explicitly supplied a valid ImpactSide from dynamic sensor filtering, honor it
                if (!string.IsNullOrWhiteSpace(request.ImpactSide) &&
                    !request.ImpactSide.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
                    !request.ImpactSide.Equals("Minor", StringComparison.OrdinalIgnoreCase) &&
                    !request.ImpactSide.Equals("None", StringComparison.OrdinalIgnoreCase) &&
                    !request.ImpactSide.Equals("-", StringComparison.OrdinalIgnoreCase))
                {
                    impactSide = request.ImpactSide.Trim();
                }
                else
                {
                    // 2. Derive impact side from directional acceleration vectors (dynamic linear shock)
                    double lr = request.AccelX;
                    double fb = request.AccelY;

                    if (lr == 0 && fb == 0 && (request.GyroX != 0 || request.GyroY != 0))
                    {
                        lr = request.GyroX;
                        fb = request.GyroY;
                    }

                    double absLR = Math.Abs(lr);
                    double absFB = Math.Abs(fb);

                    if (absLR < 0.1 && absFB < 0.1)
                    {
                        impactSide = "Front";
                    }
                    else
                    {
                        double ratio = absLR / Math.Max(absFB, 0.0001);
                        if (absLR >= 0.2 && absFB >= 0.2 && ratio >= 0.45 && ratio <= 2.2)
                        {
                            string longitudinal = fb >= 0 ? "Front" : "Rear";
                            string lateral = lr >= 0 ? "Right" : "Left";
                            impactSide = $"{longitudinal}-{lateral}";
                        }
                        else if (absFB >= absLR)
                        {
                            impactSide = fb >= 0 ? "Front" : "Rear";
                        }
                        else
                        {
                            impactSide = lr >= 0 ? "Right" : "Left";
                        }
                    }
                }

                // ================= ACCIDENT TYPE DETECTION =================
                string accidentType = "Impact";

                double totalGyroMagnitude = Math.Sqrt(gx * gx + gy * gy + gz * gz);
                bool isViolentRotation = totalGyroMagnitude > 12.0;   // Sustained violent vehicle rolling/tumbling
                bool isRollover = impactSide.Equals("Rollover", StringComparison.OrdinalIgnoreCase) || isViolentRotation;

                if (isRollover)
                {
                    accidentType = "Rollover";
                    impactSide = "Rollover";
                }
                else if (impactSide.Contains("Front", StringComparison.OrdinalIgnoreCase))
                {
                    accidentType = "Frontal Collision";
                }
                else if (impactSide.Contains("Rear", StringComparison.OrdinalIgnoreCase))
                {
                    accidentType = "Rear Collision";
                }
                else if (impactSide.Contains("Left", StringComparison.OrdinalIgnoreCase) ||
                         impactSide.Contains("Right", StringComparison.OrdinalIgnoreCase) ||
                         impactSide.Contains("Side", StringComparison.OrdinalIgnoreCase))
                {
                    accidentType = "Side Impact";
                }

                int categoryId = car.Category_Id;

                var nodeEntities = await db.Nodes
                    .Where(n => n.Category_Id == categoryId)
                    .ToListAsync();

                int startNode = ResolveStartNode(nodeEntities, categoryId, impactSide);

                // Dynamic lookup matching Force_Value with fallback to 0
                var absorption = nodeEntities
                    .ToDictionary(n => n.Node_Id, n => (double)(n.Force ?? 0.0m));

                var connectionEntities = await db.NodeConnections
                    .Where(x => x.Category_Id == categoryId)
                    .ToListAsync();

                // ================= FORCE PROPAGATION & CABIN DEAD-END =================
                var (nodeForces, deadEndForces) = PropagateForce(
                    connectionEntities, 
                    absorption, 
                    startNode, 
                    force, 
                    isRollover
                );

                // Scenario 1 (!isRollover): Force transferred into cabin when dead-end absorbs force.
                // Scenario 2 (isRollover): Dead-ends are bypassed; force rolls directly across roof/greenhouse.
                double totalDeadEndCabinForce = deadEndForces.Values.Sum();
                double cabinForce;
                if (!isRollover && totalDeadEndCabinForce > 0)
                {
                    cabinForce = totalDeadEndCabinForce;
                }
                else
                {
                    cabinForce = nodeForces.ContainsKey(13)
                        ? nodeForces[13]
                        : (nodeForces.Any() ? nodeForces.Values.Max() * 0.35 : force * 0.25);
                }

                if (isRollover)
                {
                    cabinForce *= 1.45; // Rollover roof intrusion load
                }

                double maxForce = Math.Max(force, nodeForces.Values.DefaultIfEmpty(force).Max());
                if (maxForce <= 0) maxForce = 1;

                double normalized = Math.Min(1.0, cabinForce / maxForce);
                double damage = Math.Pow(normalized, 1.6) * 100;
                if (isRollover) damage *= 1.35;
                damage = Math.Max(1.0, Math.Min(100.0, damage));

                // ================= DRIVING SIDE MODULE & PASSENGER SEVERITY =================
                // In Right-Hand Drive (RHD): Driver sits on Right, Passenger on Left.
                // In Left-Hand Drive (LHD): Driver sits on Left, Passenger on Right.
                bool isRHD = !steeringSide.Equals("Left-Hand", StringComparison.OrdinalIgnoreCase) &&
                             !steeringSide.Equals("Left", StringComparison.OrdinalIgnoreCase) &&
                             !steeringSide.Equals("LHD", StringComparison.OrdinalIgnoreCase);

                double baseOccupantForce = Math.Max(cabinForce * 0.40, effectiveAcc * 70.0);
                double baseOccupantG = baseOccupantForce / (70.0 * 9.8);

                double passengerMultiplier = 1.0;
                double driverMultiplier = 1.0;
                string occupantSummary;

                if (isRollover)
                {
                    passengerMultiplier = 1.45;
                    driverMultiplier = 1.45;
                    occupantSummary = "Rollover Hazard: Severe multi-axis roof crush danger for all occupants.";
                }
                else if (impactSide.Contains("Right", StringComparison.OrdinalIgnoreCase))
                {
                    if (isRHD)
                    {
                        // Right-Hand Drive: Driver is on Right, Passenger on Left
                        driverMultiplier = 1.25;      // Direct lateral B-pillar/door impact
                        passengerMultiplier = 0.55;   // Far side (cushioned across vehicle width)
                        occupantSummary = "RHD Vehicle: Driver in direct right-side impact zone. Passenger on Left has lateral crumple buffer.";
                    }
                    else
                    {
                        // Left-Hand Drive: Passenger is on Right, Driver on Left
                        passengerMultiplier = 1.25;   // Direct impact on Passenger side!
                        driverMultiplier = 0.55;      // Driver on far side
                        occupantSummary = "LHD Vehicle: Passenger in direct right-side impact zone! High passenger intrusion risk.";
                    }
                }
                else if (impactSide.Contains("Left", StringComparison.OrdinalIgnoreCase))
                {
                    if (isRHD)
                    {
                        // Right-Hand Drive: Passenger is on Left, Driver on Right
                        passengerMultiplier = 1.25;   // Direct impact on Passenger side!
                        driverMultiplier = 0.55;      // Driver on far side
                        occupantSummary = "RHD Vehicle: Passenger in direct left-side impact zone! High passenger intrusion risk.";
                    }
                    else
                    {
                        // Left-Hand Drive: Driver is on Left, Passenger on Right
                        driverMultiplier = 1.25;      // Direct impact on Driver side
                        passengerMultiplier = 0.55;   // Passenger on far side
                        occupantSummary = "LHD Vehicle: Driver in direct left-side impact zone. Passenger on Right has lateral crumple buffer.";
                    }
                }
                else if (impactSide.Contains("Front", StringComparison.OrdinalIgnoreCase))
                {
                    passengerMultiplier = 1.0;
                    driverMultiplier = 1.0;
                    occupantSummary = "Frontal Impact: Symmetric forward deceleration, seatbelt & airbag engagement.";
                }
                else if (impactSide.Contains("Rear", StringComparison.OrdinalIgnoreCase))
                {
                    passengerMultiplier = 0.9;
                    driverMultiplier = 0.9;
                    occupantSummary = "Rear Collision: Rearward seatback rebound and whiplash on occupants.";
                }
                else
                {
                    occupantSummary = "General structural impact.";
                }

                double passengerForce = baseOccupantForce * passengerMultiplier;
                double passengerG = baseOccupantG * passengerMultiplier;
                var (passengerAis, passengerSeverity, passengerInjury) = EvaluateOccupantInjury(passengerForce, passengerG);

                double driverForce = baseOccupantForce * driverMultiplier;
                double driverG = baseOccupantG * driverMultiplier;
                var (driverAis, driverSeverity, driverInjury) = EvaluateOccupantInjury(driverForce, driverG);

                string locationStr = (request.Latitude == 0 && request.Longitude == 0)
                    ? (string.IsNullOrEmpty(request.Location) ? "Unknown" : request.Location)
                    : $"{request.Latitude:F6},{request.Longitude:F6}";

                DateTime eventTime = request.Time ?? DateTime.Now;

                var accidentRecord = new Accident
                {
                    Car_Id = car.Car_Id,
                    Location = locationStr,
                    Impact_Side = impactSide,
                    ImpactForce = (decimal)force,
                    CabinForce = (decimal)damage,
                    Severity = $"{passengerSeverity} ({passengerAis})",
                    Time = eventTime
                };

                db.Accidents.Add(accidentRecord);
                await db.SaveChangesAsync();

                // Generate unread alert for family members and rescue
                var alert = new Alert
                {
                    Accident_Id = accidentRecord.Accident_Id,
                    Time = accidentRecord.Time,
                    Status = false
                };
                db.Alerts.Add(alert);
                await db.SaveChangesAsync();

                // Trigger push notifications for guardians and rescue teams
                try
                {
                    await _pushService.SendAccidentAlertNotificationAsync(db, accidentRecord, alert);
                }
                catch (Exception notifEx)
                {
                    Console.WriteLine($"[DetectAccident] Notification trigger error: {notifEx.Message}");
                }

                return Ok(new
                {
                    alertId = alert.Alert_Id,
                    accidentId = accidentRecord.Accident_Id,
                    carId = accidentRecord.Car_Id,
                    accidentType = accidentType,
                    impactSide = impactSide,
                    steeringSide = steeringSide,
                    impactForce = Math.Round(force, 2),
                    cabinDamage = Math.Round(damage, 2),
                    cabinForce = Math.Round(cabinForce, 2),
                    deadEndTransferForce = Math.Round(totalDeadEndCabinForce, 2),
                    isRollover = isRollover,
                    severity = $"{passengerSeverity} ({passengerAis})",
                    aisLevel = passengerAis,
                    passengerSeverity = $"{passengerSeverity} ({passengerAis})",
                    passengerInjury = passengerInjury,
                    driverSeverity = $"{driverSeverity} ({driverAis})",
                    driverInjury = driverInjury,
                    occupantSummary = occupantSummary,
                    time = accidentRecord.Time.ToString("yyyy-MM-dd HH:mm:ss"),
                    status = "ACCIDENT",
                    startNode = startNode,
                    targetNode = startNode
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { status = "ERROR", message = ex.Message });
            }
        }

        private static (string ais, string severity, string injury) EvaluateOccupantInjury(double occupantForceN, double occupantG)
        {
            // Maps measured accelerometer telemetry directly to biomechanical force and injury levels
            // according to the Crash Severity Data Matrix
            if (occupantG >= 40.0 || occupantForceN >= 27440)
            {
                return (
                    "AIS 5-6",
                    "Critical / Fatal",
                    "Critical / Fatal: High probability of life-threatening organ rupture, severe spinal injury, or death."
                );
            }
            else if (occupantG >= 20.0 || occupantForceN >= 13720)
            {
                return (
                    "AIS 3-4",
                    "Serious to Severe",
                    "Serious to Severe: Structural cabin intrusion. High risk of rib fractures, severe traumatic brain injury (TBI), or internal bleeding."
                );
            }
            else if (occupantG >= 10.0 || occupantForceN >= 6860)
            {
                return (
                    "AIS 2",
                    "Moderate",
                    "Moderate: Airbag deployment threshold (~10-15G). Seatbelt bruising, minor concussions, chest contusions, wrist/collarbone fractures."
                );
            }
            else if (occupantG >= 4.0 || occupantForceN >= 2744)
            {
                return (
                    "AIS 1",
                    "Minor",
                    "Minor: Mild neck strain/whiplash, minor soft tissue pain, superficial bruising. Airbags rarely fire."
                );
            }
            else
            {
                return (
                    "AIS 0",
                    "None",
                    "None: Normal driving, harsh braking, cornering, dropping phone, speed bumps."
                );
            }
        }

        private IActionResult NoAccident(string reason)
        {
            return Ok(new
            {
                accidentType = "None",
                impactSide = reason,
                steeringSide = "Right-Hand",
                impactForce = 0.0,
                cabinDamage = 0.0,
                cabinForce = 0.0,
                deadEndTransferForce = 0.0,
                isRollover = false,
                severity = "None (AIS 0)",
                aisLevel = "AIS 0",
                passengerSeverity = "None (AIS 0)",
                passengerInjury = "None: Normal driving, harsh braking, cornering, dropping phone, speed bumps.",
                driverSeverity = "None (AIS 0)",
                driverInjury = "None: Normal driving, harsh braking, cornering, dropping phone, speed bumps.",
                occupantSummary = "Normal driving / safe baseline.",
                status = "SAFE",
                startNode = 0,
                targetNode = 0
            });
        }

        [HttpGet("History")]
        public async Task<IActionResult> History([FromQuery] int carId)
        {
            try
            {
                if (carId <= 0)
                    return BadRequest(new { status = "ERROR", message = "Valid carId is required" });

                var records = await db.Accidents
                    .Where(a => a.Car_Id == carId)
                    .OrderByDescending(a => a.Time)
                    .Take(10)
                    .Select(a => new
                    {
                        a.Accident_Id,
                        a.Car_Id,
                        a.Location,
                        a.Impact_Side,
                        impactForce    = a.ImpactForce,
                        cabinDamage    = a.CabinForce,
                        severity       = a.Severity,
                        time           = a.Time,
                        timestamp      = a.Time
                    })
                    .ToListAsync();

                return Ok(records);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { status = "ERROR", message = ex.Message });
            }
        }

        /// <summary>
        /// Breadth-First Search Force Propagation with 2 Scenarios:
        /// Scenario 1 (!isRollover): Force propagates to neighbours until dead-end appears. 
        ///                           When an edge has Is_Cabin_Deadend = true, force transfers directly into cabin intrusion.
        /// Scenario 2 (isRollover): Is_Cabin_Deadend is bypassed completely, letting force tumble forward across roof/pillars.
        /// </summary>
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

            var graph = connections
                .GroupBy(c => c.From_Node)
                .ToDictionary(g => g.Key, g => g.ToList());

            var queue = new Queue<(int node, double force)>();
            queue.Enqueue((startNode, initialForce));

            while (queue.Count > 0)
            {
                var (node, incoming) = queue.Dequeue();

                if (visited.Contains(node)) continue;
                visited.Add(node);

                nodeForces[node] = incoming;

                double absorb = absorption.ContainsKey(node) ? absorption[node] : 0;
                double remaining = Math.Max(0, (incoming - absorb) * 0.65);

                if (remaining <= 5) continue;

                if (!graph.ContainsKey(node)) continue;

                var outboundEdges = graph[node];
                if (outboundEdges == null || outboundEdges.Count == 0) continue;

                // ================= SCENARIO HANDLING =================
                // Scenario 1 (!isRollover): Stop propagation if an edge has Is_Cabin_Deadend = true and capture remaining force.
                // Scenario 2 (isRollover): Ignore dead-ends completely and let force propagate to neighbor/roof nodes.
                foreach (var edge in outboundEdges)
                {
                    if (!isRollover && edge.Is_Cabin_Deadend)
                    {
                        if (!deadEndForces.ContainsKey(node))
                            deadEndForces[node] = 0;
                        deadEndForces[node] += remaining;
                        // Dead-end stops further chassis propagation on this path
                    }
                    else if (edge.To_Node != node && !visited.Contains(edge.To_Node))
                    {
                        double weight = (edge.Force_Weight.HasValue && edge.Force_Weight.Value > 0)
                            ? (double)edge.Force_Weight.Value
                            : (1.0 / outboundEdges.Count);
                        queue.Enqueue((edge.To_Node, remaining * weight));
                    }
                }
            }

            return (nodeForces, deadEndForces);
        }

        private int ResolveStartNode(List<Nodes> nodes, int categoryId, string impactSide)
        {
            string side = (impactSide ?? "").Trim().ToLower();

            // 1. Try exact match on Node_Position
            var exact = nodes.FirstOrDefault(n => (n.Node_Position ?? "").Trim().ToLower() == side);
            if (exact != null) return exact.Node_Id;

            // 2. Try keyword matching on Node_Position if nodes exist in DB
            if (nodes.Any())
            {
                Nodes? matched = null;

                if (side == "front")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return p.Contains("front") && (p.Contains("center") || p.Contains("grille") || p.Contains("bumper"));
                    }) ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("front"));
                }
                else if (side == "front-left")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return p.Contains("front") && p.Contains("left");
                    });
                }
                else if (side == "front-right")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return p.Contains("front") && p.Contains("right");
                    });
                }
                else if (side == "rear")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return (p.Contains("rear") || p.Contains("back")) && (p.Contains("center") || p.Contains("bumper") || p.Contains("end") || p.Contains("trunk") || p.Contains("tire"));
                    }) ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("rear") || (n.Node_Position ?? "").ToLower().Contains("back"));
                }
                else if (side == "rear-left")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return (p.Contains("rear") || p.Contains("back")) && p.Contains("left");
                    });
                }
                else if (side == "rear-right")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return (p.Contains("rear") || p.Contains("back")) && p.Contains("right");
                    });
                }
                else if (side == "left")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return p.Contains("left") && (p.Contains("door") || p.Contains("pillar") || p.Contains("mirror") || p.Contains("side"));
                    }) ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("left"));
                }
                else if (side == "right")
                {
                    matched = nodes.FirstOrDefault(n => {
                        var p = (n.Node_Position ?? "").ToLower();
                        return p.Contains("right") && (p.Contains("door") || p.Contains("pillar") || p.Contains("mirror") || p.Contains("side"));
                    }) ?? nodes.FirstOrDefault(n => (n.Node_Position ?? "").ToLower().Contains("right"));
                }

                if (matched != null) return matched.Node_Id;
            }

            // 3. Category-specific fallback matching actual vehicle blueprints
            if (categoryId == 2) // SUV
            {
                switch (impactSide)
                {
                    case "Front": return 1;
                    case "Front-Left": return 3;
                    case "Front-Right": return 2;
                    case "Left": return 10;
                    case "Right": return 13;
                    case "Rear": return 24;
                    case "Rear-Left": return 23;
                    case "Rear-Right": return 25;
                    default: return 1;
                }
            }
            else if (categoryId == 3) // Hatchback
            {
                switch (impactSide)
                {
                    case "Front": return 1;
                    case "Front-Left": return 2;
                    case "Front-Right": return 3;
                    case "Left": return 16;
                    case "Right": return 17;
                    case "Rear": return 23;
                    case "Rear-Left": return 21;
                    case "Rear-Right": return 22;
                    default: return 1;
                }
            }
            else // Sedan (Category 1 or default)
            {
                switch (impactSide)
                {
                    case "Front": return 1;
                    case "Front-Left": return 2;
                    case "Front-Right": return 3;
                    case "Left": return 15;
                    case "Right": return 17;
                    case "Rear": return 30;
                    case "Rear-Left": return 28;
                    case "Rear-Right": return 29;
                    default: return 1;
                }
            }
        }
    }
}
*/


using Accident_Detection_Backend.Models;
using Accident_Detection_Backend.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Linq;
using System.Threading.Tasks;

namespace AccidentDetectionApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class DetectAccidentController : ControllerBase
    {
        private readonly AppDbContext db;
        private readonly PushNotificationService _pushService;

        // In-memory cache for live victim location updates (ultra-fast polling without database thrashing)
        private static readonly ConcurrentDictionary<int, (double Latitude, double Longitude, DateTime UpdatedAt)> _liveLocations = new();

        public DetectAccidentController(AppDbContext context, PushNotificationService pushService)
        {
            db = context;
            _pushService = pushService;
        }

        [HttpPost("ImpactCalculation")]
        public async Task<IActionResult> ImpactCalculation([FromBody] AccidentRequest request)
        {
            try
            {
                if (request == null)
                    return BadRequest(new { status = "ERROR", message = "Invalid Request Body" });

                double acc = request.Acceleration;
                double gx = request.GyroX;
                double gy = request.GyroY;
                double gz = request.GyroZ;

                // ============================================================
                // MINIMUM IMPACT ACCELERATION
                // Ignore small taps, vibrations and normal phone movement.
                // ============================================================
                const double MIN_IMPACT_ACCELERATION = 2.0;

                if (acc < MIN_IMPACT_ACCELERATION)
                    return NoAccident("Impact Too Weak");

                var car = await db.Cars.FirstOrDefaultAsync(c => c.Car_Id == request.CarId);

                if (car == null)
                {
                    car = await db.Cars.FirstOrDefaultAsync();

                    if (car == null)
                        return NotFound(new
                        {
                            status = "ERROR",
                            message = "Car not found"
                        });
                }

                // Determine driving side (Right-Hand vs Left-Hand)
                string steeringSide = !string.IsNullOrWhiteSpace(request.SteeringSide)
                    ? request.SteeringSide.Trim()
                    : (!string.IsNullOrWhiteSpace(car.Steering_Side)
                        ? car.Steering_Side.Trim()
                        : "Right-Hand");

                var category = await db.Categories
                    .FirstOrDefaultAsync(x => x.Category_Id == car.Category_Id);

                double weightTon = Convert.ToDouble(category?.Weight ?? 1.5m);

                if (weightTon <= 0)
                    weightTon = 1.5;

                double mass = weightTon * 1000;

                // ============================================================
                // PALM-HIT TEST FORCE AMPLIFICATION
                // Reduced from 3.5 to 1.5 so small taps do not
                // become artificially large collision forces.
                // ============================================================
                const double PALM_TEST_FORCE_MULTIPLIER = 1.5;

                double effectiveAcc = acc * PALM_TEST_FORCE_MULTIPLIER;
                double force = mass * effectiveAcc * 0.75;

                if (force < 200)
                    return NoAccident("Minor Vibration");

                if (Math.Abs(gz) > 3.0 && acc < 3.5)
                    return NoAccident("Speed Breaker");

                // ================= EXACT IMPACT SIDE DETECTION =================
                string impactSide;

                // 1. If caller explicitly supplied a valid ImpactSide from dynamic sensor filtering, honor it
                if (!string.IsNullOrWhiteSpace(request.ImpactSide) &&
                    !request.ImpactSide.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
                    !request.ImpactSide.Equals("Minor", StringComparison.OrdinalIgnoreCase) &&
                    !request.ImpactSide.Equals("None", StringComparison.OrdinalIgnoreCase) &&
                    !request.ImpactSide.Equals("-", StringComparison.OrdinalIgnoreCase))
                {
                    impactSide = request.ImpactSide.Trim();
                }
                else
                {
                    // 2. Derive impact side from directional acceleration vectors (dynamic linear shock)
                    double lr = request.AccelX;
                    double fb = request.AccelY;

                    if (lr == 0 && fb == 0 && (request.GyroX != 0 || request.GyroY != 0))
                    {
                        lr = request.GyroX;
                        fb = request.GyroY;
                    }

                    double absLR = Math.Abs(lr);
                    double absFB = Math.Abs(fb);

                    if (absLR < 0.1 && absFB < 0.1)
                    {
                        impactSide = "Front";
                    }
                    else
                    {
                        double ratio = absLR / Math.Max(absFB, 0.0001);

                        if (absLR >= 0.2 &&
                            absFB >= 0.2 &&
                            ratio >= 0.45 &&
                            ratio <= 2.2)
                        {
                            string longitudinal = fb >= 0 ? "Front" : "Rear";
                            string lateral = lr >= 0 ? "Right" : "Left";

                            impactSide = $"{longitudinal}-{lateral}";
                        }
                        else if (absFB >= absLR)
                        {
                            impactSide = fb >= 0 ? "Front" : "Rear";
                        }
                        else
                        {
                            impactSide = lr >= 0 ? "Right" : "Left";
                        }
                    }
                }

                // ================= ACCIDENT TYPE DETECTION =================
                string accidentType = "Impact";

                double totalGyroMagnitude =
                    Math.Sqrt(gx * gx + gy * gy + gz * gz);

                bool isViolentRotation = totalGyroMagnitude > 12.0;

                bool isRollover =
                    impactSide.Equals("Rollover", StringComparison.OrdinalIgnoreCase)
                    || isViolentRotation;

                if (isRollover)
                {
                    accidentType = "Rollover";
                    impactSide = "Rollover";
                }
                else if (impactSide.Contains("Front", StringComparison.OrdinalIgnoreCase))
                {
                    accidentType = "Frontal Collision";
                }
                else if (impactSide.Contains("Rear", StringComparison.OrdinalIgnoreCase))
                {
                    accidentType = "Rear Collision";
                }
                else if (
                    impactSide.Contains("Left", StringComparison.OrdinalIgnoreCase) ||
                    impactSide.Contains("Right", StringComparison.OrdinalIgnoreCase) ||
                    impactSide.Contains("Side", StringComparison.OrdinalIgnoreCase))
                {
                    accidentType = "Side Impact";
                }

                int categoryId = car.Category_Id;

                var nodeEntities = await db.Nodes
                    .Where(n => n.Category_Id == categoryId)
                    .ToListAsync();

                int startNode =
                    ResolveStartNode(nodeEntities, categoryId, impactSide);

                // Dynamic lookup matching Force_Value with fallback to 0
                var absorption = nodeEntities
                    .ToDictionary(
                        n => n.Node_Id,
                        n => (double)(n.Force ?? 0.0m)
                    );

                var connectionEntities = await db.NodeConnections
                    .Where(x => x.Category_Id == categoryId)
                    .ToListAsync();

                // ================= FORCE PROPAGATION & CABIN DEAD-END =================
                var (nodeForces, deadEndForces) = PropagateForce(
                    connectionEntities,
                    absorption,
                    startNode,
                    force,
                    isRollover
                );

                // Scenario 1 (!isRollover):
                // Force transferred into cabin when dead-end absorbs force.
                //
                // Scenario 2 (isRollover):
                // Dead-ends are bypassed; force rolls directly across roof/greenhouse.
                double totalDeadEndCabinForce =
                    deadEndForces.Values.Sum();

                double cabinForce;

                if (!isRollover && totalDeadEndCabinForce > 0)
                {
                    cabinForce = totalDeadEndCabinForce;
                }
                else
                {
                    cabinForce = nodeForces.ContainsKey(13)
                        ? nodeForces[13]
                        : (
                            nodeForces.Any()
                                ? nodeForces.Values.Max() * 0.35
                                : force * 0.25
                          );
                }

                if (isRollover)
                {
                    cabinForce *= 1.45;
                }

                double maxForce =
                    Math.Max(
                        force,
                        nodeForces.Values
                            .DefaultIfEmpty(force)
                            .Max()
                    );

                if (maxForce <= 0)
                    maxForce = 1;

                double normalized =
                    Math.Min(1.0, cabinForce / maxForce);

                double damage =
                    Math.Pow(normalized, 1.6) * 100;

                if (isRollover)
                    damage *= 1.35;

                damage =
                    Math.Max(
                        1.0,
                        Math.Min(100.0, damage)
                    );

                // ================= DRIVING SIDE MODULE & PASSENGER SEVERITY =================
                // In Right-Hand Drive (RHD): Driver sits on Right, Passenger on Left.
                // In Left-Hand Drive (LHD): Driver sits on Left, Passenger on Right.

                bool isRHD =
                    !steeringSide.Equals(
                        "Left-Hand",
                        StringComparison.OrdinalIgnoreCase
                    ) &&
                    !steeringSide.Equals(
                        "Left",
                        StringComparison.OrdinalIgnoreCase
                    ) &&
                    !steeringSide.Equals(
                        "LHD",
                        StringComparison.OrdinalIgnoreCase
                    );

                double baseOccupantForce =
                    Math.Max(
                        cabinForce * 0.40,
                        effectiveAcc * 70.0
                    );

                double baseOccupantG =
                    baseOccupantForce / (70.0 * 9.8);

                double passengerMultiplier = 1.0;
                double driverMultiplier = 1.0;

                string occupantSummary;

                if (isRollover)
                {
                    passengerMultiplier = 1.45;
                    driverMultiplier = 1.45;

                    occupantSummary =
                        "Rollover Hazard: Severe multi-axis roof crush danger for all occupants.";
                }
                else if (impactSide.Contains(
                    "Right",
                    StringComparison.OrdinalIgnoreCase))
                {
                    if (isRHD)
                    {
                        driverMultiplier = 1.25;
                        passengerMultiplier = 0.55;

                        occupantSummary =
                            "RHD Vehicle: Driver in direct right-side impact zone. Passenger on Left has lateral crumple buffer.";
                    }
                    else
                    {
                        passengerMultiplier = 1.25;
                        driverMultiplier = 0.55;

                        occupantSummary =
                            "LHD Vehicle: Passenger in direct right-side impact zone! High passenger intrusion risk.";
                    }
                }
                else if (impactSide.Contains(
                    "Left",
                    StringComparison.OrdinalIgnoreCase))
                {
                    if (isRHD)
                    {
                        passengerMultiplier = 1.25;
                        driverMultiplier = 0.55;

                        occupantSummary =
                            "RHD Vehicle: Passenger in direct left-side impact zone! High passenger intrusion risk.";
                    }
                    else
                    {
                        driverMultiplier = 1.25;
                        passengerMultiplier = 0.55;

                        occupantSummary =
                            "LHD Vehicle: Driver in direct left-side impact zone. Passenger on Right has lateral crumple buffer.";
                    }
                }
                else if (impactSide.Contains(
                    "Front",
                    StringComparison.OrdinalIgnoreCase))
                {
                    passengerMultiplier = 1.0;
                    driverMultiplier = 1.0;

                    occupantSummary =
                        "Frontal Impact: Symmetric forward deceleration, seatbelt & airbag engagement.";
                }
                else if (impactSide.Contains(
                    "Rear",
                    StringComparison.OrdinalIgnoreCase))
                {
                    passengerMultiplier = 0.9;
                    driverMultiplier = 0.9;

                    occupantSummary =
                        "Rear Collision: Rearward seatback rebound and whiplash on occupants.";
                }
                else
                {
                    occupantSummary = "General structural impact.";
                }

                double passengerForce =
                    baseOccupantForce * passengerMultiplier;

                double passengerG =
                    baseOccupantG * passengerMultiplier;

                var (
                    passengerAis,
                    passengerSeverity,
                    passengerInjury
                ) = EvaluateOccupantInjury(
                    passengerForce,
                    passengerG
                );

                double driverForce =
                    baseOccupantForce * driverMultiplier;

                double driverG =
                    baseOccupantG * driverMultiplier;

                var (
                    driverAis,
                    driverSeverity,
                    driverInjury
                ) = EvaluateOccupantInjury(
                    driverForce,
                    driverG
                );

                string locationStr =
                    (request.Latitude == 0 &&
                     request.Longitude == 0)
                    ? (
                        string.IsNullOrEmpty(request.Location)
                            ? "Unknown"
                            : request.Location
                      )
                    : $"{request.Latitude:F6},{request.Longitude:F6}";

                DateTime eventTime =
                    request.Time ?? DateTime.Now;

                var accidentRecord = new Accident
                {
                    Car_Id = car.Car_Id,
                    Location = locationStr,
                    Impact_Side = impactSide,
                    ImpactForce = (decimal)force,
                    CabinForce = (decimal)damage,
                    Severity = $"{passengerSeverity} ({passengerAis})",
                    Time = eventTime
                };

                db.Accidents.Add(accidentRecord);

                await db.SaveChangesAsync();

                // Generate unread alert for family members and rescue
                var alert = new Alert
                {
                    Accident_Id = accidentRecord.Accident_Id,
                    Time = accidentRecord.Time,
                    Status = false
                };

                db.Alerts.Add(alert);

                await db.SaveChangesAsync();

                // Trigger push notifications for guardians and rescue teams
                try
                {
                    await _pushService.SendAccidentAlertNotificationAsync(
                        db,
                        accidentRecord,
                        alert
                    );
                }
                catch (Exception notifEx)
                {
                    Console.WriteLine(
                        $"[DetectAccident] Notification trigger error: {notifEx.Message}"
                    );
                }

                return Ok(new
                {
                    alertId = alert.Alert_Id,
                    accidentId = accidentRecord.Accident_Id,
                    carId = accidentRecord.Car_Id,
                    accidentType = accidentType,
                    impactSide = impactSide,
                    steeringSide = steeringSide,
                    impactForce = Math.Round(force, 2),
                    cabinDamage = Math.Round(damage, 2),
                    cabinForce = Math.Round(cabinForce, 2),
                    deadEndTransferForce =
                        Math.Round(totalDeadEndCabinForce, 2),
                    isRollover = isRollover,
                    severity =
                        $"{passengerSeverity} ({passengerAis})",
                    aisLevel = passengerAis,
                    passengerSeverity =
                        $"{passengerSeverity} ({passengerAis})",
                    passengerInjury = passengerInjury,
                    driverSeverity =
                        $"{driverSeverity} ({driverAis})",
                    driverInjury = driverInjury,
                    occupantSummary = occupantSummary,
                    time =
                        accidentRecord.Time.ToString(
                            "yyyy-MM-dd HH:mm:ss"
                        ),
                    status = "ACCIDENT",
                    startNode = startNode,
                    targetNode = startNode
                });
            }
            catch (Exception ex)
            {
                return StatusCode(
                    500,
                    new
                    {
                        status = "ERROR",
                        message = ex.Message
                    }
                );
            }
        }

        // ================= UPDATE LIVE LOCATION (VICTIM APP) =================
        // POST: api/DetectAccident/UpdateLiveLocation
        [HttpPost("UpdateLiveLocation")]
        public async Task<IActionResult> UpdateLiveLocation([FromBody] UpdateLiveLocationRequest request)
        {
            try
            {
                if (request == null || request.AccidentId <= 0)
                    return BadRequest(new { status = "ERROR", message = "Valid accidentId is required." });

                if (request.Latitude < -90.0 || request.Latitude > 90.0 || request.Longitude < -180.0 || request.Longitude > 180.0)
                    return BadRequest(new { status = "ERROR", message = "Coordinates out of valid geographical range." });

                var now = DateTime.UtcNow;

                // 1. Thread-safe in-memory cache for fast polling
                _liveLocations[request.AccidentId] = (request.Latitude, request.Longitude, now);

                // 2. Persist to existing database Accident.Location column (No database schema change needed)
                var accident = await db.Accidents.FirstOrDefaultAsync(a => a.Accident_Id == request.AccidentId);
                if (accident != null)
                {
                    accident.Location = $"{request.Latitude.ToString(System.Globalization.CultureInfo.InvariantCulture)},{request.Longitude.ToString(System.Globalization.CultureInfo.InvariantCulture)}";
                    await db.SaveChangesAsync();
                }
                else
                {
                    return NotFound(new { status = "ERROR", message = "Accident record not found." });
                }

                return Ok(new
                {
                    status = "SUCCESS",
                    message = "Live location updated successfully",
                    accidentId = request.AccidentId,
                    latitude = request.Latitude,
                    longitude = request.Longitude,
                    updatedAt = now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { status = "ERROR", message = ex.Message });
            }
        }

        // ================= GET LIVE LOCATION (FAMILY / RESCUE APP) =================
        // GET: api/DetectAccident/LiveLocation?accidentId=123
        [HttpGet("LiveLocation")]
        public async Task<IActionResult> GetLiveLocation([FromQuery] int accidentId)
        {
            try
            {
                if (accidentId <= 0)
                    return BadRequest(new { status = "ERROR", message = "Valid accidentId is required." });

                // 1. Check in-memory store first
                if (_liveLocations.TryGetValue(accidentId, out var entry))
                {
                    return Ok(new
                    {
                        accidentId = accidentId,
                        latitude = entry.Latitude,
                        longitude = entry.Longitude,
                        updatedAt = entry.UpdatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                        status = "LIVE"
                    });
                }

                // 2. Fallback to existing database Accident record
                var accident = await db.Accidents.FirstOrDefaultAsync(a => a.Accident_Id == accidentId);
                if (accident == null)
                    return NotFound(new { status = "ERROR", message = "Accident record not found." });

                double lat = 0.0;
                double lon = 0.0;

                if (!string.IsNullOrWhiteSpace(accident.Location))
                {
                    var parts = accident.Location.Split(',');
                    if (parts.Length >= 2 &&
                        double.TryParse(parts[0].Trim(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var parsedLat) &&
                        double.TryParse(parts[1].Trim(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var parsedLon))
                    {
                        lat = parsedLat;
                        lon = parsedLon;
                    }
                }

                return Ok(new
                {
                    accidentId = accidentId,
                    latitude = lat,
                    longitude = lon,
                    updatedAt = accident.Time.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                    status = "LAST_KNOWN"
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { status = "ERROR", message = ex.Message });
            }
        }

        private static (
            string ais,
            string severity,
            string injury
        ) EvaluateOccupantInjury(
            double occupantForceN,
            double occupantG)
        {
            // Maps measured accelerometer telemetry directly to biomechanical force and injury levels
            // according to the Crash Severity Data Matrix

            if (occupantG >= 40.0 ||
                occupantForceN >= 27440)
            {
                return (
                    "AIS 5-6",
                    "Critical / Fatal",
                    "Critical / Fatal: High probability of life-threatening organ rupture, severe spinal injury, or death."
                );
            }
            else if (occupantG >= 20.0 ||
                     occupantForceN >= 13720)
            {
                return (
                    "AIS 3-4",
                    "Serious to Severe",
                    "Serious to Severe: Structural cabin intrusion. High risk of rib fractures, severe traumatic brain injury (TBI), or internal bleeding."
                );
            }
            else if (occupantG >= 10.0 ||
                     occupantForceN >= 6860)
            {
                return (
                    "AIS 2",
                    "Moderate",
                    "Moderate: Airbag deployment threshold (~10-15G). Seatbelt bruising, minor concussions, chest contusions, wrist/collarbone fractures."
                );
            }
            else if (occupantG >= 4.0 ||
                     occupantForceN >= 2744)
            {
                return (
                    "AIS 1",
                    "Minor",
                    "Minor: Mild neck strain/whiplash, minor soft tissue pain, superficial bruising. Airbags rarely fire."
                );
            }
            else
            {
                return (
                    "AIS 0",
                    "None",
                    "None: Normal driving, harsh braking, cornering, dropping phone, speed bumps."
                );
            }
        }

        private IActionResult NoAccident(string reason)
        {
            return Ok(new
            {
                accidentType = "None",
                impactSide = reason,
                steeringSide = "Right-Hand",
                impactForce = 0.0,
                cabinDamage = 0.0,
                cabinForce = 0.0,
                deadEndTransferForce = 0.0,
                isRollover = false,
                severity = "None (AIS 0)",
                aisLevel = "AIS 0",
                passengerSeverity = "None (AIS 0)",
                passengerInjury =
                    "None: Normal driving, harsh braking, cornering, dropping phone, speed bumps.",
                driverSeverity = "None (AIS 0)",
                driverInjury =
                    "None: Normal driving, harsh braking, cornering, dropping phone, speed bumps.",
                occupantSummary = "Normal driving / safe baseline.",
                status = "SAFE",
                startNode = 0,
                targetNode = 0
            });
        }

        [HttpGet("History")]
        public async Task<IActionResult> History(
            [FromQuery] int carId)
        {
            try
            {
                if (carId <= 0)
                    return BadRequest(
                        new
                        {
                            status = "ERROR",
                            message = "Valid carId is required"
                        });

                var records = await db.Accidents
                    .Where(a => a.Car_Id == carId)
                    .OrderByDescending(a => a.Time)
                    .Take(10)
                    .Select(a => new
                    {
                        a.Accident_Id,
                        a.Car_Id,
                        a.Location,
                        a.Impact_Side,
                        impactForce = a.ImpactForce,
                        cabinDamage = a.CabinForce,
                        severity = a.Severity,
                        time = a.Time,
                        timestamp = a.Time
                    })
                    .ToListAsync();

                return Ok(records);
            }
            catch (Exception ex)
            {
                return StatusCode(
                    500,
                    new
                    {
                        status = "ERROR",
                        message = ex.Message
                    });
            }
        }

        /// <summary>
        /// Breadth-First Search Force Propagation with 2 Scenarios:
        /// Scenario 1 (!isRollover): Force propagates to neighbours until dead-end appears.
        ///                           When an edge has Is_Cabin_Deadend = true,
        ///                           force transfers directly into cabin intrusion.
        /// Scenario 2 (isRollover): Is_Cabin_Deadend is bypassed completely,
        ///                           letting force tumble forward across roof/pillars.
        /// </summary>
        private (
            Dictionary<int, double> nodeForces,
            Dictionary<int, double> deadEndForces
        ) PropagateForce(
            List<NodeConnection> connections,
            Dictionary<int, double> absorption,
            int startNode,
            double initialForce,
            bool isRollover)
        {
            var visited = new HashSet<int>();

            var nodeForces =
                new Dictionary<int, double>();

            var deadEndForces =
                new Dictionary<int, double>();

            var graph = connections
                .GroupBy(c => c.From_Node)
                .ToDictionary(
                    g => g.Key,
                    g => g.ToList()
                );

            var queue =
                new Queue<(int node, double force)>();

            queue.Enqueue(
                (startNode, initialForce)
            );

            while (queue.Count > 0)
            {
                var (node, incoming) =
                    queue.Dequeue();

                if (visited.Contains(node))
                    continue;

                visited.Add(node);

                nodeForces[node] = incoming;

                double absorb =
                    absorption.ContainsKey(node)
                        ? absorption[node]
                        : 0;

                double remaining =
                    Math.Max(
                        0,
                        (incoming - absorb) * 0.65
                    );

                if (remaining <= 5)
                    continue;

                if (!graph.ContainsKey(node))
                    continue;

                var outboundEdges =
                    graph[node];

                if (outboundEdges == null ||
                    outboundEdges.Count == 0)
                    continue;

                // ================= SCENARIO HANDLING =================
                // Scenario 1 (!isRollover):
                // Stop propagation if an edge has Is_Cabin_Deadend = true
                // and capture remaining force.
                //
                // Scenario 2 (isRollover):
                // Ignore dead-ends completely and let force propagate
                // to neighbor/roof nodes.

                foreach (var edge in outboundEdges)
                {
                    if (!isRollover &&
                        edge.Is_Cabin_Deadend)
                    {
                        if (!deadEndForces.ContainsKey(node))
                            deadEndForces[node] = 0;

                        deadEndForces[node] += remaining;

                        // Dead-end stops further chassis propagation on this path
                    }
                    else if (
                        edge.To_Node != node &&
                        !visited.Contains(edge.To_Node))
                    {
                        double weight =
                            (
                                edge.Force_Weight.HasValue &&
                                edge.Force_Weight.Value > 0
                            )
                            ? (double)edge.Force_Weight.Value
                            : (1.0 / outboundEdges.Count);

                        queue.Enqueue(
                            (
                                edge.To_Node,
                                remaining * weight
                            )
                        );
                    }
                }
            }

            return (
                nodeForces,
                deadEndForces
            );
        }

        private int ResolveStartNode(
            List<Nodes> nodes,
            int categoryId,
            string impactSide)
        {
            string side =
                (impactSide ?? "")
                .Trim()
                .ToLower();

            // 1. Try exact match on Node_Position
            var exact =
                nodes.FirstOrDefault(
                    n =>
                        (n.Node_Position ?? "")
                        .Trim()
                        .ToLower() == side
                );

            if (exact != null)
                return exact.Node_Id;

            // 2. Try keyword matching on Node_Position if nodes exist in DB
            if (nodes.Any())
            {
                Nodes? matched = null;

                if (side == "front")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return p.Contains("front") &&
                                   (
                                       p.Contains("center") ||
                                       p.Contains("grille") ||
                                       p.Contains("bumper")
                                   );
                        })
                        ??
                        nodes.FirstOrDefault(
                            n =>
                                (n.Node_Position ?? "")
                                .ToLower()
                                .Contains("front")
                        );
                }
                else if (side == "front-left")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return p.Contains("front") &&
                                   p.Contains("left");
                        });
                }
                else if (side == "front-right")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return p.Contains("front") &&
                                   p.Contains("right");
                        });
                }
                else if (side == "rear")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return (
                                       p.Contains("rear") ||
                                       p.Contains("back")
                                   )
                                   &&
                                   (
                                       p.Contains("center") ||
                                       p.Contains("bumper") ||
                                       p.Contains("end") ||
                                       p.Contains("trunk") ||
                                       p.Contains("tire")
                                   );
                        })
                        ??
                        nodes.FirstOrDefault(
                            n =>
                                (n.Node_Position ?? "")
                                .ToLower()
                                .Contains("rear")
                                ||
                                (n.Node_Position ?? "")
                                .ToLower()
                                .Contains("back")
                        );
                }
                else if (side == "rear-left")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return (
                                       p.Contains("rear") ||
                                       p.Contains("back")
                                   )
                                   &&
                                   p.Contains("left");
                        });
                }
                else if (side == "rear-right")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return (
                                       p.Contains("rear") ||
                                       p.Contains("back")
                                   )
                                   &&
                                   p.Contains("right");
                        });
                }
                else if (side == "left")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return p.Contains("left") &&
                                   (
                                       p.Contains("door") ||
                                       p.Contains("pillar") ||
                                       p.Contains("mirror") ||
                                       p.Contains("side")
                                   );
                        })
                        ??
                        nodes.FirstOrDefault(
                            n =>
                                (n.Node_Position ?? "")
                                .ToLower()
                                .Contains("left")
                        );
                }
                else if (side == "right")
                {
                    matched =
                        nodes.FirstOrDefault(n =>
                        {
                            var p =
                                (n.Node_Position ?? "")
                                .ToLower();

                            return p.Contains("right") &&
                                   (
                                       p.Contains("door") ||
                                       p.Contains("pillar") ||
                                       p.Contains("mirror") ||
                                       p.Contains("side")
                                   );
                        })
                        ??
                        nodes.FirstOrDefault(
                            n =>
                                (n.Node_Position ?? "")
                                .ToLower()
                                .Contains("right")
                        );
                }

                if (matched != null)
                    return matched.Node_Id;
            }

            // 3. Category-specific fallback matching actual vehicle blueprints
            if (categoryId == 2) // SUV
            {
                switch (impactSide)
                {
                    case "Front":
                        return 1;

                    case "Front-Left":
                        return 3;

                    case "Front-Right":
                        return 2;

                    case "Left":
                        return 10;

                    case "Right":
                        return 13;

                    case "Rear":
                        return 24;

                    case "Rear-Left":
                        return 23;

                    case "Rear-Right":
                        return 25;

                    default:
                        return 1;
                }
            }
            else if (categoryId == 3) // Hatchback
            {
                switch (impactSide)
                {
                    case "Front":
                        return 1;

                    case "Front-Left":
                        return 2;

                    case "Front-Right":
                        return 3;

                    case "Left":
                        return 16;

                    case "Right":
                        return 17;

                    case "Rear":
                        return 23;

                    case "Rear-Left":
                        return 21;

                    case "Rear-Right":
                        return 22;

                    default:
                        return 1;
                }
            }
            else // Sedan (Category 1 or default)
            {
                switch (impactSide)
                {
                    case "Front":
                        return 1;

                    case "Front-Left":
                        return 2;

                    case "Front-Right":
                        return 3;

                    case "Left":
                        return 15;

                    case "Right":
                        return 17;

                    case "Rear":
                        return 30;

                    case "Rear-Left":
                        return 28;

                    case "Rear-Right":
                        return 29;

                    default:
                        return 1;
                }
            }
        }
    }
}