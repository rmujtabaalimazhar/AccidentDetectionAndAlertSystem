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
                Accident accident = new Accident()
                {
                    Car_Id = request.CarId,
                    Location = request.Location ?? "Unknown",
                    Impact_Side = request.ImpactSide, // Used ImpactSide from model
                    ImpactForce = (decimal)force,
                    CabinForce = (decimal)damage
                };

                db.Accidents.Add(accident);

                // ✅ IMPORTANT: CHECK RESULT
                int result = db.SaveChanges();

                // 🔥 DEBUG LOG
                System.Diagnostics.Debug.WriteLine("Rows Affected: " + result);

                if (result > 0)
                {
                    return Ok(new
                    {
                        message = "Saved Successfully",
                        saved = true,
                        force,
                        damage
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
                        lastEvent = "-"
                    });
                }

                return Ok(new
                {
                    impactSide = last.Impact_Side,
                    force = (last.ImpactForce.HasValue && last.ImpactForce > 0) ? "ON" : "OFF",
                    cabinDamage = last.CabinForce ?? 0,
                    lastEvent = DateTime.Now
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }
    }
}