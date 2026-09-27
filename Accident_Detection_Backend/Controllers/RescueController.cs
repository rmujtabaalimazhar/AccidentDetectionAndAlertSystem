using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Accident_Detection_Backend.Models;

namespace Accident_Detection_Backend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class RescueController : ControllerBase
    {
        private readonly AppDbContext _context;

        public RescueController(AppDbContext context)
        {
            _context = context;
        }

        // ================= RESCUE REGISTER =================
        // POST: api/Rescue/Register
        public class RescueRegisterRequest
        {
            public string Password { get; set; } = null!;
            public string? Location { get; set; }
        }

        [HttpPost("Register")]
        public async Task<IActionResult> Register([FromBody] RescueRegisterRequest request)
        {
            if (request == null || string.IsNullOrWhiteSpace(request.Password))
                return BadRequest(new { message = "Password is required for rescue registration." });

            try
            {
                var rescue = new Rescue
                {
                    Password = request.Password,
                    Location = string.IsNullOrWhiteSpace(request.Location) ? "0.0,0.0" : request.Location.Trim()
                };

                _context.Rescues.Add(rescue);
                await _context.SaveChangesAsync();

                return Ok(new
                {
                    message = "Rescue Team registered successfully.",
                    rid = rescue.Rid,
                    location = rescue.Location,
                    role = "rescue"
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= RESCUE LOGIN =================
        // POST: api/Rescue/Login
        public class RescueLoginRequest
        {
            public int Rid { get; set; }
            public string Password { get; set; } = null!;
        }

        [HttpPost("Login")]
        public async Task<IActionResult> Login([FromBody] RescueLoginRequest request)
        {
            if (request == null || request.Rid <= 0 || string.IsNullOrWhiteSpace(request.Password))
                return BadRequest(new { message = "Rescue ID and password are required." });

            try
            {
                var rescue = await _context.Rescues
                    .FirstOrDefaultAsync(r => r.Rid == request.Rid && r.Password == request.Password);

                if (rescue == null)
                    return Unauthorized(new { message = "Invalid Rescue ID or password." });

                return Ok(new
                {
                    message = "Rescue login successful.",
                    rid = rescue.Rid,
                    location = rescue.Location,
                    role = "rescue"
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= UPDATE RESCUE LOCATION =================
        // PUT: api/Rescue/UpdateLocation
        public class UpdateLocationRequest
        {
            public int Rid { get; set; }
            public string Location { get; set; } = null!;
        }

        [HttpPut("UpdateLocation")]
        public async Task<IActionResult> UpdateLocation([FromBody] UpdateLocationRequest request)
        {
            if (request == null || request.Rid <= 0 || string.IsNullOrWhiteSpace(request.Location))
                return BadRequest(new { message = "Rid and Location are required." });

            try
            {
                var rescue = await _context.Rescues.FindAsync(request.Rid);
                if (rescue == null)
                    return NotFound(new { message = "Rescue unit not found." });

                rescue.Location = request.Location.Trim();
                await _context.SaveChangesAsync();

                return Ok(new
                {
                    message = "Location updated successfully.",
                    rid = rescue.Rid,
                    location = rescue.Location
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }
    }
}
