using Accident_Detection_Backend.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System;
using System.Linq;

namespace Accident_Detection_Backend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class LocationController : ControllerBase
    {
        private readonly AppDbContext db;

        public LocationController(AppDbContext context)
        {
            db = context;
        }

        // ================= ADD ACCIDENT =================
        [HttpPost("AddAccident")]
        public IActionResult AddAccident([FromBody] AccidentRequest request)
        {
            try
            {
                if (request == null)
                {
                    return BadRequest("Invalid Request");
                }

                // ✅ GET CAR WITH CATEGORY
                var car = db.Cars
                    .Include(c => c.Category)
                    .FirstOrDefault(c => c.Car_Id == request.CarId); // Used CarId from model

                if (car == null)
                {
                    return NotFound("Car Not Found");
                }

                // ✅ WEIGHT FIX
                double weightTon = 1.5;

                if (car.Category != null && car.Category.Weight.HasValue)
                {
                    weightTon = (double)car.Category.Weight.Value;
                }

                double mass = weightTon * 1000;
                double acceleration = request.Acceleration;

                // ✅ FORCE CALCULATION
                double force = mass * acceleration;

                // ✅ DAMAGE CALCULATION
                double damage = (force / 5000) * 100;
                if (damage > 100) damage = 100;

                // ================= SAVE =================
                string severity = !string.IsNullOrWhiteSpace(request.Severity)
                    ? request.Severity
                    : (damage >= 70 ? "High" : damage >= 30 ? "Medium" : "Low");

                DateTime eventTime = request.Time ?? DateTime.Now;

                Accident accident = new Accident()
                {
                    Car_Id = request.CarId,
                    Location = request.Location ?? "Unknown",
                    Impact_Side = request.ImpactSide, // Used ImpactSide from model
                    ImpactForce = (decimal)force,
                    CabinForce = (decimal)damage,
                    Severity = severity,
                    Time = eventTime
                };

                db.Accidents.Add(accident);

                // ✅ IMPORTANT: CHECK RESULT
                int result = db.SaveChanges();

                if (result > 0)
                {
                    // Generate unread alert for family members and rescue
                    var alert = new Alert
                    {
                        Accident_Id = accident.Accident_Id,
                        Time = accident.Time,
                        Status = false
                    };
                    db.Alerts.Add(alert);
                    db.SaveChanges();

                    return Ok(new
                    {
                        message = "Saved Successfully",
                        saved = true,
                        force,
                        damage,
                        severity = accident.Severity,
                        time = accident.Time.ToString("yyyy-MM-dd HH:mm:ss"),
                        alertId = alert.Alert_Id
                    });
                }
                else
                {
                    return StatusCode(500, "Data not saved");
                }
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }

        // ================= GET LATEST =================
        [HttpGet("latest")]
        public IActionResult Latest()
        {
            try
            {
                var last = db.Accidents
                    .OrderByDescending(a => a.Accident_Id)
                    .FirstOrDefault();

                if (last == null)
                {
                    return Ok(new
                    {
                        impactSide = "-",
                        force = "OFF",
                        cabinDamage = 0,
                        severity = "-",
                        time = (DateTime?)null,
                        lastEvent = "-"
                    });
                }

                return Ok(new
                {
                    impactSide = last.Impact_Side,
                    force = (last.ImpactForce.HasValue && last.ImpactForce > 0) ? "ON" : "OFF",
                    cabinDamage = last.CabinForce ?? 0,
                    severity = last.Severity ?? "-",
                    time = last.Time,
                    lastEvent = last.Time.ToString("yyyy-MM-dd HH:mm:ss")
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }
    }
}