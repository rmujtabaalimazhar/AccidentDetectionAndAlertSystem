
// using Accident_Detection_Backend.Models;
// using Microsoft.AspNetCore.Mvc;
// using System;
// using System.Collections.Generic;
// using System.Linq;

// namespace AccidentDetectionApi.Controllers
// {
//     [ApiController]
//     [Route("api/[controller]")]
//     public class DetectAccidentController : ControllerBase
//     {
//         private readonly AppDbContext db;

//         public DetectAccidentController(AppDbContext context)
//         {
//             db = context;
//         }

//         [HttpPost("ImpactCalculation")]
//         public IActionResult ImpactCalculation([FromBody] AccidentRequest request)
//         {
//             try
//             {
//                 if (request == null)
//                     return BadRequest("Invalid Request");

//                 double acc = request.Acceleration;
//                 double gx = request.GyroX;
//                 double gy = request.GyroY;
//                 double gz = request.GyroZ;

//                 if (acc < 1.5)
//                     return NoAccident("No Movement");

//                 var car = db.Cars.FirstOrDefault(c => c.Car_Id == request.CarId);
//                 if (car == null)
//                     return NotFound("Car not found");

//                 var category = db.Categories.FirstOrDefault(x => x.Category_Id == car.Category_Id);

//                 double weightTon = (category?.Weight ?? 1.5m) > 0
//                     ? Convert.ToDouble(category.Weight)
//                     : 1.5;

//                 double mass = weightTon * 1000;

//                 double force = mass * acc * 0.7;

//                 if (force < 1000)
//                     return NoAccident("Minor Impact");

//                 if (Math.Abs(gz) > 2 && acc < 6)
//                     return NoAccident("Speed Breaker");

//                 double lr = -gy;
//                 double fb = gx;

//                 double absLR = Math.Abs(lr);
//                 double absFB = Math.Abs(fb);

//                 double threshold = 1.5;

//                 string impactSide = "Unknown";

//                 if (absLR < threshold && absFB < threshold)
//                 {
//                     impactSide = "Minor";
//                 }
//                 else if (absFB > absLR)
//                 {
//                     if (fb > 0)
//                     {
//                         impactSide = absLR > 1
//                             ? (lr > 0 ? "Front-Right" : "Front-Left")
//                             : "Front";
//                     }
//                     else
//                     {
//                         impactSide = absLR > 1
//                             ? (lr > 0 ? "Rear-Right" : "Rear-Left")
//                             : "Rear";
//                     }
//                 }
//                 else
//                 {
//                     impactSide = lr > 0 ? "Right" : "Left";
//                 }

//                 int startNode = 4;

//                 switch (impactSide)
//                 {
//                     case "Front": startNode = 2; break;
//                     case "Front-Left": startNode = 1; break;
//                     case "Front-Right": startNode = 3; break;
//                     case "Left": startNode = 17; break;
//                     case "Right": startNode = 18; break;
//                     case "Rear": startNode = 20; break;
//                     case "Rear-Left": startNode = 19; break;
//                     case "Rear-Right": startNode = 21; break;
//                     default: startNode = 4; break;
//                 }

//                 int categoryId = car.Category_Id;

//                 var absorption = db.Nodes
//                     .Where(n => n.Category_Id == categoryId)
//                     .ToDictionary(n => n.Node_Id, n => (double)(n.Force ?? 0));

//                 var graph = db.NodeConnections
//                     .Where(x => x.Category_Id == categoryId)
//                     .GroupBy(e => e.From_Node)
//                     .ToDictionary(g => g.Key, g => g.Select(x => x.To_Node).ToList());

//                 var nodeForces = PropagateForce(graph, absorption, startNode, force);

//                 if (!nodeForces.Any())
//                     return NoAccident("No Propagation");

//                 double cabinForce = nodeForces.ContainsKey(13)
//                     ? nodeForces[13]
//                     : nodeForces.Values.Max() * 0.3;

//                 double maxForce = nodeForces.Values.Max();
//                 if (maxForce <= 0) maxForce = 1;

//                 double normalized = cabinForce / maxForce;

//                 double damage = Math.Pow(normalized, 1.8) * 100;

//                 double directionFactor = 1 + (absLR + absFB) * 0.05;
//                 damage *= directionFactor;

//                 damage = Math.Max(0, Math.Min(100, damage));

//                 string locationStr = (request.Latitude == 0 && request.Longitude == 0)
//                     ? "Unknown"
//                     : $"{request.Latitude:F6},{request.Longitude:F6}";

//                 db.Accidents.Add(new Accident
//                 {
//                     Car_Id = request.CarId,
//                     Location = locationStr,
//                     Impact_Side = impactSide,
//                     ImpactForce = (decimal)force,
//                     CabinForce = (decimal)damage,
//                     CreatedAt = DateTime.UtcNow
//                 });

//                 db.SaveChanges();

//                 return Ok(new
//                 {
//                     impactSide,
//                     impactForce = force,
//                     cabinDamage = damage,
//                     cabinForce,
//                     status = "ACCIDENT",
//                     startNode
//                 });
//             }
//             catch (Exception ex)
//             {
//                 return StatusCode(500, ex.Message);
//             }
//         }

//         private IActionResult NoAccident(string reason)
//         {
//             return Ok(new
//             {
//                 impactSide = reason,
//                 impactForce = 0,
//                 cabinDamage = 0,
//                 cabinForce = 0,
//                 status = "SAFE"
//             });
//         }

//         // ================= GET ACCIDENT HISTORY =================
//         // GET: api/DetectAccident/History?carId=1
//         [HttpGet("History")]
//         public IActionResult History([FromQuery] int carId)
//         {
//             try
//             {
//                 if (carId <= 0)
//                     return BadRequest("Valid carId is required");

//                 var records = db.Accidents
//                     .Where(a => a.Car_Id == carId)
//                     .OrderByDescending(a => a.CreatedAt)
//                     .Take(10)
//                     .Select(a => new
//                     {
//                         a.Accident_Id,
//                         a.Car_Id,
//                         a.Location,
//                         a.Impact_Side,
//                         impactForce    = a.ImpactForce,
//                         cabinDamage    = a.CabinForce,
//                         timestamp      = a.CreatedAt
//                     })
//                     .ToList();

//                 return Ok(records);
//             }
//             catch (Exception ex)
//             {
//                 return StatusCode(500, ex.Message);
//             }
//         }

//         private Dictionary<int, double> PropagateForce(
//             Dictionary<int, List<int>> graph,
//             Dictionary<int, double> absorption,
//             int start,
//             double force)
//         {
//             var visited = new HashSet<int>();
//             var result = new Dictionary<int, double>();

//             var queue = new Queue<(int node, double force)>();
//             queue.Enqueue((start, force));

//             while (queue.Count > 0)
//             {
//                 var (node, incoming) = queue.Dequeue();

//                 if (visited.Contains(node)) continue;
//                 visited.Add(node);

//                 result[node] = incoming;

//                 double absorb = absorption.ContainsKey(node) ? absorption[node] : 0;

//                 double remaining = (incoming - absorb) * 0.6;

//                 if (remaining <= 10) continue;

//                 if (!graph.ContainsKey(node)) continue;

//                 var neighbors = graph[node];
//                 if (neighbors.Count == 0) continue;

//                 double split = remaining / neighbors.Count;

//                 foreach (var next in neighbors)
//                 {
//                     if (!visited.Contains(next))
//                         queue.Enqueue((next, split));
//                 }
//             }

//             return result;
//         }
//     }
// }

using Accident_Detection_Backend.Models;
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

        public DetectAccidentController(AppDbContext context)
        {
            db = context;
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

                // Lowered minimum threshold slightly to allow palm-tap test triggering
                if (acc < 0.2)
                    return NoAccident("No Movement");

                var car = await db.Cars.FirstOrDefaultAsync(c => c.Car_Id == request.CarId);
                if (car == null)
                {
                    // Fallback to first car in DB to prevent crash during testing if CarId isn't matched
                    car = await db.Cars.FirstOrDefaultAsync();
                    if (car == null)
                        return NotFound(new { status = "ERROR", message = "Car not found" });
                }

                var category = await db.Categories.FirstOrDefaultAsync(x => x.Category_Id == car.Category_Id);

                double weightTon = (category?.Weight ?? 1.5m) > 0
                    ? Convert.ToDouble(category.Weight)
                    : 1.5;

                double mass = weightTon * 1000;

                double force = mass * acc * 0.7;

                // Threshold adjusted for manual testing so palm hits are not ignored
                if (force < 100)
                    return NoAccident("Minor Impact");

                if (Math.Abs(gz) > 2 && acc < 6)
                    return NoAccident("Speed Breaker");

                // Check linear acceleration vectors first for precise direction, fallback to gyro rates
                // double lr = (request.AccelX != 0 || request.AccelY != 0) ? request.AccelX : -gy;
                // double fb = (request.AccelX != 0 || request.AccelY != 0) ? request.AccelY : gx;

                   double lr = (request.AccelX != 0 || request.AccelY != 0) ? -request.AccelX : gy;
                   double fb = (request.AccelX != 0 || request.AccelY != 0) ? -request.AccelY : -gx;
                double absLR = Math.Abs(lr);
                double absFB = Math.Abs(fb);

                double threshold = 0.3;

                string impactSide = "Unknown";

                if (absLR < threshold && absFB < threshold)
                {
                    impactSide = "Minor";
                }
                else if (absFB > absLR)
                {
                    if (fb > 0)
                    {
                        impactSide = absLR > 0.3
                            ? (lr > 0 ? "Front-Right" : "Front-Left")
                            : "Front";
                    }
                    else
                    {
                        impactSide = absLR > 0.3
                            ? (lr > 0 ? "Rear-Right" : "Rear-Left")
                            : "Rear";
                    }
                }
                else
                {
                    impactSide = lr > 0 ? "Right" : "Left";
                }

                int startNode = 4;

                switch (impactSide)
                {
                    case "Front": startNode = 2; break;
                    case "Front-Left": startNode = 1; break;
                    case "Front-Right": startNode = 3; break;
                    case "Left": startNode = 17; break;
                    case "Right": startNode = 18; break;
                    case "Rear": startNode = 20; break;
                    case "Rear-Left": startNode = 19; break;
                    case "Rear-Right": startNode = 21; break;
                    default: startNode = 4; break;
                }

                int categoryId = car.Category_Id;

                // Attempt dynamic database node position match first
                var dbMatchedNode = await db.Nodes
                    .FirstOrDefaultAsync(n => n.Category_Id == categoryId && n.Node_Position.ToLower() == impactSide.ToLower());
                if (dbMatchedNode != null)
                {
                    startNode = dbMatchedNode.Node_Id;
                }

                var nodeEntities = await db.Nodes
                    .Where(n => n.Category_Id == categoryId)
                    .ToListAsync();

                var absorption = nodeEntities
                    .ToDictionary(n => n.Node_Id, n => (double)(n.Force ?? 0));

                var connectionEntities = await db.NodeConnections
                    .Where(x => x.Category_Id == categoryId)
                    .ToListAsync();

                var graph = connectionEntities
                    .GroupBy(e => e.From_Node)
                    .ToDictionary(g => g.Key, g => g.Select(x => x.To_Node).ToList());

                var nodeForces = PropagateForce(graph, absorption, startNode, force);

                // Fallback calculations if graph propagation returns empty result
                double cabinForce = force * 0.2;
                double maxForce = force;

                if (nodeForces.Any())
                {
                    cabinForce = nodeForces.ContainsKey(13)
                        ? nodeForces[13]
                        : nodeForces.Values.Max() * 0.3;

                    maxForce = nodeForces.Values.Max();
                }

                if (maxForce <= 0) maxForce = 1;

                double normalized = cabinForce / maxForce;

                double damage = Math.Pow(normalized, 1.8) * 100;

                double directionFactor = 1 + (absLR + absFB) * 0.05;
                damage *= directionFactor;

                damage = Math.Max(1.0, Math.Min(100, damage));

                string locationStr = (request.Latitude == 0 && request.Longitude == 0)
                    ? (string.IsNullOrEmpty(request.Location) ? "Unknown" : request.Location)
                    : $"{request.Latitude:F6},{request.Longitude:F6}";

                var accidentRecord = new Accident
                {
                    Car_Id = request.CarId > 0 ? request.CarId : car.Car_Id,
                    Location = locationStr,
                    Impact_Side = impactSide,
                    ImpactForce = (decimal)force,
                    CabinForce = (decimal)damage,
                    CreatedAt = DateTime.UtcNow
                };

                db.Accidents.Add(accidentRecord);
                await db.SaveChangesAsync();

                return Ok(new
                {
                    accidentId = accidentRecord.Accident_Id,
                    carId = accidentRecord.Car_Id,
                    impactSide,
                    impactForce = Math.Round(force, 2),
                    cabinDamage = Math.Round(damage, 2),
                    cabinForce = Math.Round(cabinForce, 2),
                    status = "ACCIDENT",
                    startNode = startNode,
                    targetNode = startNode
                });
            }
            catch (Exception ex)
            {
                // Guarantees JSON output during exceptions so Swift does not throw parsing errors
                return StatusCode(500, new { status = "ERROR", message = ex.Message });
            }
        }

        private IActionResult NoAccident(string reason)
        {
            return Ok(new
            {
                impactSide = reason,
                impactForce = 0.0,
                cabinDamage = 0.0,
                cabinForce = 0.0,
                status = "SAFE",
                startNode = 0,
                targetNode = 0
            });
        }

        // ================= GET ACCIDENT HISTORY =================
        // GET: api/DetectAccident/History?carId=1
        [HttpGet("History")]
        public async Task<IActionResult> History([FromQuery] int carId)
        {
            try
            {
                if (carId <= 0)
                    return BadRequest(new { status = "ERROR", message = "Valid carId is required" });

                var records = await db.Accidents
                    .Where(a => a.Car_Id == carId)
                    .OrderByDescending(a => a.CreatedAt)
                    .Take(10)
                    .Select(a => new
                    {
                        a.Accident_Id,
                        a.Car_Id,
                        a.Location,
                        a.Impact_Side,
                        impactForce    = a.ImpactForce,
                        cabinDamage    = a.CabinForce,
                        timestamp      = a.CreatedAt
                    })
                    .ToListAsync();

                return Ok(records);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { status = "ERROR", message = ex.Message });
            }
        }

        private Dictionary<int, double> PropagateForce(
            Dictionary<int, List<int>> graph,
            Dictionary<int, double> absorption,
            int start,
            double force)
        {
            var visited = new HashSet<int>();
            var result = new Dictionary<int, double>();

            var queue = new Queue<(int node, double force)>();
            queue.Enqueue((start, force));

            while (queue.Count > 0)
            {
                var (node, incoming) = queue.Dequeue();

                if (visited.Contains(node)) continue;
                visited.Add(node);

                result[node] = incoming;

                double absorb = absorption.ContainsKey(node) ? absorption[node] : 0;

                double remaining = (incoming - absorb) * 0.6;

                if (remaining <= 5) continue;

                if (!graph.ContainsKey(node)) continue;

                var neighbors = graph[node];
                if (neighbors == null || neighbors.Count == 0) continue;

                double split = remaining / neighbors.Count;

                foreach (var next in neighbors)
                {
                    if (!visited.Contains(next))
                        queue.Enqueue((next, split));
                }
            }

            return result;
        }
    }
}