using System;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Accident_Detection_Backend.Models;

namespace Accident_Detection_Backend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AlertsController : ControllerBase
    {
        private readonly AppDbContext _context;

        public AlertsController(AppDbContext context)
        {
            _context = context;
        }

        // ================= GET GUARDIAN ALERTS =================
        // GET: api/Alerts/Guardian?guardianId=user@example.com
        [HttpGet("Guardian")]
        public async Task<IActionResult> GetGuardianAlerts([FromQuery] string guardianId)
        {
            if (string.IsNullOrWhiteSpace(guardianId))
                return BadRequest(new { message = "Guardian ID is required." });

            try
            {
                // Find all users who have this person as their guardian
                var familyLinks = await _context.FamilyMembers
                    .Where(f => f.Guardian_Id == guardianId.Trim())
                    .ToListAsync();

                if (!familyLinks.Any())
                    return Ok(new List<object>());

                var userUids = familyLinks.Select(f => f.Uid).Distinct().ToList();

                // Fetch unread alerts for accidents on cars belonging to these users
                var alerts = await _context.Alerts
                    .Include(a => a.Accident)
                        .ThenInclude(acc => acc!.Car)
                            .ThenInclude(c => c!.User)
                    .Where(a => a.Status == false &&
                                a.Accident != null &&
                                a.Accident.Car != null &&
                                userUids.Contains(a.Accident.Car.Uid))
                    .OrderByDescending(a => a.Time)
                    .ToListAsync();

                var results = alerts.Select(a =>
                {
                    var driverUid = a.Accident?.Car?.Uid ?? "";
                    var link = familyLinks.FirstOrDefault(f => f.Uid.Equals(driverUid, StringComparison.OrdinalIgnoreCase));

                    return new
                    {
                        alertId = a.Alert_Id,
                        accidentId = a.Accident_Id,
                        time = a.Time.ToString("yyyy-MM-dd HH:mm:ss"),
                        status = a.Status,
                        driverUid = driverUid,
                        driverName = a.Accident?.Car?.User?.Name ?? driverUid,
                        driverContact = a.Accident?.Car?.User?.Contact_No ?? "",
                        relationship = link?.Relationship ?? "Family Member",
                        carMake = a.Accident?.Car?.Make ?? "Vehicle",
                        plateNumber = a.Accident?.Car?.Registration_No ?? "-",
                        location = a.Accident?.Location ?? "Unknown",
                        impactSide = a.Accident?.Impact_Side ?? "-",
                        impactForce = a.Accident?.ImpactForce ?? 0,
                        cabinDamage = a.Accident?.CabinForce ?? 0,
                        severity = a.Accident?.Severity ?? "Medium"
                    };
                }).ToList();

                return Ok(results);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= GET RESCUE ALERTS (MINIMUM DISTANCE) =================
        // GET: api/Alerts/Rescue?rid=1
        [HttpGet("Rescue")]
        public async Task<IActionResult> GetRescueAlerts([FromQuery] int rid)
        {
            if (rid <= 0)
                return BadRequest(new { message = "Valid Rescue ID is required." });

            try
            {
                var myRescue = await _context.Rescues.FindAsync(rid);
                if (myRescue == null)
                    return NotFound(new { message = "Rescue unit not found." });

                var allRescues = await _context.Rescues.ToListAsync();

                // Fetch all unread alerts
                var unreadAlerts = await _context.Alerts
                    .Include(a => a.Accident)
                        .ThenInclude(acc => acc!.Car)
                            .ThenInclude(c => c!.User)
                    .Where(a => a.Status == false && a.Accident != null)
                    .OrderByDescending(a => a.Time)
                    .ToListAsync();

                var results = new List<object>();

                foreach (var alert in unreadAlerts)
                {
                    var accLoc = ParseCoordinates(alert.Accident?.Location);

                    // If coordinates are parseable, determine nearest rescue
                    if (accLoc.HasValue)
                    {
                        int closestRid = rid;
                        double minDistance = double.MaxValue;
                        double myDistance = double.MaxValue;

                        foreach (var r in allRescues)
                        {
                            var rLoc = ParseCoordinates(r.Location);
                            if (rLoc.HasValue)
                            {
                                double d = CalculateDistanceKm(accLoc.Value.lat, accLoc.Value.lon, rLoc.Value.lat, rLoc.Value.lon);
                                if (d < minDistance)
                                {
                                    minDistance = d;
                                    closestRid = r.Rid;
                                }
                                if (r.Rid == rid)
                                {
                                    myDistance = d;
                                }
                            }
                        }

                        // Check if this rescue unit is the closest or if only one rescue exists
                        if (closestRid == rid || allRescues.Count <= 1 || myDistance <= minDistance + 0.1)
                        {
                            results.Add(new
                            {
                                alertId = alert.Alert_Id,
                                accidentId = alert.Accident_Id,
                                time = alert.Time.ToString("yyyy-MM-dd HH:mm:ss"),
                                status = alert.Status,
                                driverUid = alert.Accident?.Car?.Uid ?? "",
                                driverName = alert.Accident?.Car?.User?.Name ?? "Driver",
                                driverContact = alert.Accident?.Car?.User?.Contact_No ?? "",
                                relationship = "Rescue Dispatch",
                                carMake = alert.Accident?.Car?.Make ?? "Vehicle",
                                plateNumber = alert.Accident?.Car?.Registration_No ?? "-",
                                location = alert.Accident?.Location ?? "Unknown",
                                impactSide = alert.Accident?.Impact_Side ?? "-",
                                impactForce = alert.Accident?.ImpactForce ?? 0,
                                cabinDamage = alert.Accident?.CabinForce ?? 0,
                                severity = alert.Accident?.Severity ?? "High",
                                distanceKm = myDistance < double.MaxValue ? Math.Round(myDistance, 2) : 0.0
                            });
                        }
                    }
                    else
                    {
                        // Fallback if no precise coords: broadcast to active rescue
                        results.Add(new
                        {
                            alertId = alert.Alert_Id,
                            accidentId = alert.Accident_Id,
                            time = alert.Time.ToString("yyyy-MM-dd HH:mm:ss"),
                            status = alert.Status,
                            driverUid = alert.Accident?.Car?.Uid ?? "",
                            driverName = alert.Accident?.Car?.User?.Name ?? "Driver",
                            driverContact = alert.Accident?.Car?.User?.Contact_No ?? "",
                            relationship = "Rescue Dispatch",
                            carMake = alert.Accident?.Car?.Make ?? "Vehicle",
                            plateNumber = alert.Accident?.Car?.Registration_No ?? "-",
                            location = alert.Accident?.Location ?? "Unknown",
                            impactSide = alert.Accident?.Impact_Side ?? "-",
                            impactForce = alert.Accident?.ImpactForce ?? 0,
                            cabinDamage = alert.Accident?.CabinForce ?? 0,
                            severity = alert.Accident?.Severity ?? "High",
                            distanceKm = 0.0
                        });
                    }
                }

                return Ok(results);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= MARK ALERT AS SEEN =================
        // POST: api/Alerts/MarkAsSeen?alertId=1
        [HttpPost("MarkAsSeen")]
        public async Task<IActionResult> MarkAsSeen([FromQuery] int alertId)
        {
            if (alertId <= 0)
                return BadRequest(new { message = "Valid Alert ID is required." });

            try
            {
                var alert = await _context.Alerts.FindAsync(alertId);
                if (alert == null)
                    return NotFound(new { message = "Alert not found." });

                alert.Status = true;
                await _context.SaveChangesAsync();

                return Ok(new
                {
                    message = "Alert marked as seen.",
                    alertId = alert.Alert_Id,
                    status = alert.Status
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= GEOLOCATION HELPERS =================
        private static double CalculateDistanceKm(double lat1, double lon1, double lat2, double lon2)
        {
            double r = 6371.0; // Earth radius in km
            double dLat = (lat2 - lat1) * Math.PI / 180.0;
            double dLon = (lon2 - lon1) * Math.PI / 180.0;
            double a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                       Math.Cos(lat1 * Math.PI / 180.0) * Math.Cos(lat2 * Math.PI / 180.0) *
                       Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
            double c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
            return r * c;
        }

        private static (double lat, double lon)? ParseCoordinates(string? locStr)
        {
            if (string.IsNullOrWhiteSpace(locStr)) return null;

            var parts = locStr.Split(',');
            if (parts.Length >= 2 &&
                double.TryParse(parts[0].Trim(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out double lat) &&
                double.TryParse(parts[1].Trim(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out double lon))
            {
                return (lat, lon);
            }
            return null;
        }
    }
}
