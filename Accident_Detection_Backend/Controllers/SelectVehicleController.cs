using Accident_Detection_Backend.Models;
using Microsoft.AspNetCore.Mvc;
using System;
using System.Linq;

namespace Accident_Detection_Backend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class SelectVehicleController : ControllerBase
    {
        private readonly AppDbContext db;

        public SelectVehicleController(AppDbContext context)
        {
            db = context;
        }

        // ================= GET USER VEHICLES =================
        // ✅ URL: api/SelectVehicle/UserVehicles?uid=email
        [HttpGet("UserVehicles")]
        public IActionResult UserVehicles([FromQuery] string uid)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(uid))
                {
                    return BadRequest("User email is required");
                }

                var cars = db.Cars
                    .Where(c => c.Uid == uid)
                    .Select(c => new
                    {
                        Car_Id = c.Car_Id,
                        Make = c.Make,
                        Registration_No = c.Registration_No,
                        Category_Id = c.Category_Id,
                        Steering_Side = c.Steering_Side
                    })
                    .ToList();

                return Ok(cars);
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }

        // ================= ADD VEHICLE =================
        // ✅ URL: api/SelectVehicle/AddVehicle
        [HttpPost("AddVehicle")]
        public IActionResult AddVehicle([FromBody] Car car)
        {
            try
            {
                if (car == null ||
                    string.IsNullOrWhiteSpace(car.Registration_No) ||
                    string.IsNullOrWhiteSpace(car.Uid))
                {
                    return BadRequest("Invalid vehicle data");
                }

                if (string.IsNullOrWhiteSpace(car.Steering_Side))
                {
                    car.Steering_Side = "Right-Hand";
                }

                if (db.Cars.Any(c => c.Registration_No == car.Registration_No))
                {
                    return Conflict("Vehicle already exists");
                }

                db.Cars.Add(car);
                db.SaveChanges();

                return Ok("Vehicle Added Successfully");
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }

        // ================= REMOVE VEHICLE =================
        // ✅ URL: api/SelectVehicle/RemoveVehicle?carId=1
        [HttpDelete("RemoveVehicle")]
        public IActionResult RemoveVehicle([FromQuery] int carId)
        {
            try
            {
                var car = db.Cars.FirstOrDefault(c => c.Car_Id == carId);

                if (car == null)
                {
                    return NotFound("Vehicle not found");
                }

                db.Cars.Remove(car);
                db.SaveChanges();

                return Ok("Vehicle removed successfully");
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }
    }
}
