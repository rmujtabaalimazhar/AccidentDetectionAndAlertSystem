
using Accident_Detection_Backend.Models;
using Microsoft.AspNetCore.Mvc;
using System;
using System.Collections.Generic;
using System.Linq;

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
        public IActionResult ImpactCalculation([FromBody] AccidentRequest request)
        {
            try
            {
                if (request == null)
                    return BadRequest("Invalid Request");

                double acc = request.Acceleration;
                double gx = request.GyroX;
                double gy = request.GyroY;
                double gz = request.GyroZ;

                if (acc < 1.5)
                    return NoAccident("No Movement");

                var car = db.Cars.FirstOrDefault(c => c.Car_Id == request.CarId);
                if (car == null)
                    return NotFound("Car not found");

                var category = db.Categories.FirstOrDefault(x => x.Category_Id == car.Category_Id);

                double weightTon = (category?.Weight ?? 1.5m) > 0
                    ? Convert.ToDouble(category.Weight)
                    : 1.5;

                double mass = weightTon * 1000;

                double force = mass * acc * 0.7;

                if (force < 1000)
                    return NoAccident("Minor Impact");

                if (Math.Abs(gz) > 2 && acc < 6)
                    return NoAccident("Speed Breaker");

                double lr = -gy;
                double fb = gx;

                double absLR = Math.Abs(lr);
                double absFB = Math.Abs(fb);

                double threshold = 1.5;

                string impactSide = "Unknown";

                if (absLR < threshold && absFB < threshold)
                {
                    impactSide = "Minor";
                }
                else if (absFB > absLR)
                {
                    if (fb > 0)
                    {
                        impactSide = absLR > 1
                            ? (lr > 0 ? "Front-Right" : "Front-Left")
                            : "Front";
                    }
                    else
                    {
                        impactSide = absLR > 1
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

                var absorption = db.Nodes
                    .Where(n => n.Category_Id == categoryId)
                    .ToDictionary(n => n.Node_Id, n => (double)(n.Force ?? 0));

                var graph = db.NodeConnections
                    .Where(x => x.Category_Id == categoryId)
                    .GroupBy(e => e.From_Node)
                    .ToDictionary(g => g.Key, g => g.Select(x => x.To_Node).ToList());

                var nodeForces = PropagateForce(graph, absorption, startNode, force);

                if (!nodeForces.Any())
                    return NoAccident("No Propagation");

                double cabinForce = nodeForces.ContainsKey(13)
                    ? nodeForces[13]
                    : nodeForces.Values.Max() * 0.3;

                double maxForce = nodeForces.Values.Max();
                if (maxForce <= 0) maxForce = 1;

                double normalized = cabinForce / maxForce;

                double damage = Math.Pow(normalized, 1.8) * 100;

                double directionFactor = 1 + (absLR + absFB) * 0.05;
                damage *= directionFactor;

                damage = Math.Max(0, Math.Min(100, damage));

                string locationStr = (request.Latitude == 0 && request.Longitude == 0)
                    ? "Unknown"
                    : $"{request.Latitude:F6},{request.Longitude:F6}";

                db.Accidents.Add(new Accident
                {
                    Car_Id = request.CarId,
                    Location = locationStr,
                    Impact_Side = impactSide,
                    ImpactForce = (decimal)force,
                    CabinForce = (decimal)damage,
                    CreatedAt = DateTime.UtcNow
                });

                db.SaveChanges();

                return Ok(new
                {
                    impactSide,
                    impactForce = force,
                    cabinDamage = damage,
                    cabinForce,
                    status = "ACCIDENT",
                    startNode
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }

        private IActionResult NoAccident(string reason)
        {
            return Ok(new
            {
                impactSide = reason,
                impactForce = 0,
                cabinDamage = 0,
                cabinForce = 0,
                status = "SAFE"
            });
        }

        // ================= GET ACCIDENT HISTORY =================
        // GET: api/DetectAccident/History?carId=1
        [HttpGet("History")]
        public IActionResult History([FromQuery] int carId)
        {
            try
            {
                if (carId <= 0)
                    return BadRequest("Valid carId is required");

                var records = db.Accidents
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
                    .ToList();

                return Ok(records);
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
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

                if (remaining <= 10) continue;

                if (!graph.ContainsKey(node)) continue;

                var neighbors = graph[node];
                if (neighbors.Count == 0) continue;

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
