using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Accident_Detection_Backend.Models;
using Accident_Detection_Backend.Services;

namespace Accident_Detection_Backend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class NotificationsController : ControllerBase
    {
        private readonly AppDbContext _context;
        private readonly PushNotificationService _pushService;

        public NotificationsController(AppDbContext context, PushNotificationService pushService)
        {
            _context = context;
            _pushService = pushService;
        }

        public class DeviceTokenRequest
        {
            public string UserIdentifier { get; set; } = null!;
            public string UserType { get; set; } = "Guardian"; // "Guardian", "Rescue", or "User"
            public string Token { get; set; } = null!;
            public string Platform { get; set; } = "iOS";
        }

        // ================= REGISTER OR UPDATE DEVICE TOKEN =================
        // POST: api/Notifications/RegisterToken
        [HttpPost("RegisterToken")]
        public async Task<IActionResult> RegisterToken([FromBody] DeviceTokenRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.UserIdentifier) || string.IsNullOrWhiteSpace(req.Token))
            {
                return BadRequest(new { message = "UserIdentifier and Token are required." });
            }

            try
            {
                var existing = await _context.DeviceTokens
                    .FirstOrDefaultAsync(d => d.UserIdentifier == req.UserIdentifier.Trim() && d.Token == req.Token.Trim());

                if (existing != null)
                {
                    existing.UserType = req.UserType;
                    existing.Platform = req.Platform ?? "iOS";
                    existing.UpdatedAt = DateTime.UtcNow;
                }
                else
                {
                    var tokenRecord = new DeviceToken
                    {
                        UserIdentifier = req.UserIdentifier.Trim(),
                        UserType = req.UserType,
                        Token = req.Token.Trim(),
                        Platform = req.Platform ?? "iOS",
                        UpdatedAt = DateTime.UtcNow
                    };
                    _context.DeviceTokens.Add(tokenRecord);
                }

                await _context.SaveChangesAsync();
                return Ok(new { message = "Device token registered successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= CHECK PENDING ALERTS FOR BACKGROUND FETCH =================
        // GET: api/Notifications/CheckPending?userType=Guardian&id=guardian@example.com&lastAlertId=0
        [HttpGet("CheckPending")]
        public async Task<IActionResult> CheckPending(
            [FromQuery] string userType,
            [FromQuery] string id,
            [FromQuery] int lastAlertId = 0)
        {
            if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(userType))
            {
                return BadRequest(new { message = "Both userType and id are required." });
            }

            try
            {
                if (userType.Equals("Guardian", StringComparison.OrdinalIgnoreCase) ||
                    userType.Equals("User", StringComparison.OrdinalIgnoreCase))
                {
                    // Find users for whom this person is a guardian
                    var familyLinks = await _context.FamilyMembers
                        .Where(f => f.Guardian_Id == id.Trim())
                        .ToListAsync();

                    if (!familyLinks.Any())
                        return Ok(new { hasNewAlerts = false, count = 0, alerts = Array.Empty<object>() });

                    var driverUids = familyLinks.Select(f => f.Uid).Distinct().ToList();

                    var newAlerts = await _context.Alerts
                        .Include(a => a.Accident)
                            .ThenInclude(acc => acc!.Car)
                                .ThenInclude(c => c!.User)
                        .Where(a => a.Status == false &&
                                    a.Alert_Id > lastAlertId &&
                                    a.Accident != null &&
                                    a.Accident.Car != null &&
                                    driverUids.Contains(a.Accident.Car.Uid))
                        .OrderByDescending(a => a.Alert_Id)
                        .ToListAsync();

                    var results = newAlerts.Select(a => new
                    {
                        alertId = a.Alert_Id,
                        accidentId = a.Accident_Id,
                        time = a.Time.ToString("yyyy-MM-dd HH:mm:ss"),
                        driverName = a.Accident?.Car?.User?.Name ?? a.Accident?.Car?.Uid ?? "Driver",
                        carMake = a.Accident?.Car?.Make ?? "Vehicle",
                        plateNumber = a.Accident?.Car?.Registration_No ?? "-",
                        location = a.Accident?.Location ?? "Unknown",
                        severity = a.Accident?.Severity ?? "High",
                        impactForce = a.Accident?.ImpactForce ?? 0
                    }).ToList();

                    return Ok(new
                    {
                        hasNewAlerts = results.Count > 0,
                        count = results.Count,
                        alerts = results
                    });
                }
                else if (userType.Equals("Rescue", StringComparison.OrdinalIgnoreCase))
                {
                    if (!int.TryParse(id.Trim(), out int rid))
                        return BadRequest(new { message = "Invalid Rescue ID." });

                    var newAlerts = await _context.Alerts
                        .Include(a => a.Accident)
                            .ThenInclude(acc => acc!.Car)
                                .ThenInclude(c => c!.User)
                        .Where(a => a.Status == false &&
                                    a.Alert_Id > lastAlertId &&
                                    a.Accident != null)
                        .OrderByDescending(a => a.Alert_Id)
                        .ToListAsync();

                    var results = newAlerts.Select(a => new
                    {
                        alertId = a.Alert_Id,
                        accidentId = a.Accident_Id,
                        time = a.Time.ToString("yyyy-MM-dd HH:mm:ss"),
                        driverName = a.Accident?.Car?.User?.Name ?? "Driver",
                        carMake = a.Accident?.Car?.Make ?? "Vehicle",
                        plateNumber = a.Accident?.Car?.Registration_No ?? "-",
                        location = a.Accident?.Location ?? "Unknown",
                        severity = a.Accident?.Severity ?? "High",
                        impactForce = a.Accident?.ImpactForce ?? 0
                    }).ToList();

                    return Ok(new
                    {
                        hasNewAlerts = results.Count > 0,
                        count = results.Count,
                        alerts = results
                    });
                }

                return BadRequest(new { message = "Unsupported userType. Use 'Guardian' or 'Rescue'." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }
    }
}
