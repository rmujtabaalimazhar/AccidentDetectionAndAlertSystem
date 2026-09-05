using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Accident_Detection_Backend.Models;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Linq;

namespace Accident_Detection_Backend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AuthController : ControllerBase
    {
        private readonly AppDbContext _context;

        public AuthController(AppDbContext context)
        {
            _context = context;
        }

        // ✅ CREATE USER (like your old CreateUser)
        [HttpPost("CreateUser")]
        public async Task<ActionResult<User>>  CreateUser(User user)
        {
            if (user == null)
            {
                return BadRequest("Invalid user data.");
            }

            var existingUser = await _context.Users
                .FirstOrDefaultAsync(u => u.Uid == user.Uid);

            if (existingUser != null)
            {
                return Conflict("User already exists with this email.");
            }

            _context.Users.Add(user);
            await _context.SaveChangesAsync();

            return Ok("User Registered Successfully");
        }

        // ✅ LOGIN (same logic as your old code)
        [HttpPost("Login")]
        public async Task<IActionResult> Login(string email, string pas)
        {
            try
            {
                var data = await _context.Users
                    .FirstOrDefaultAsync(p => p.Uid == email && p.Password == pas);

                if (data == null)
                {
                    return Unauthorized("Invalid email or password");
                }

                return Ok(data);
            }
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }

        // ✅ FORGOT PASSWORD (same logic)
        [HttpPost("ForgotPassword")]
        public async Task<IActionResult> ForgotPassword(string email, string newPassword, string confirmPassword)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(email) ||
                    string.IsNullOrWhiteSpace(newPassword) ||
                    string.IsNullOrWhiteSpace(confirmPassword))
                {
                    return BadRequest("All fields are required");
                }

                if (newPassword != confirmPassword)
                {
                    return BadRequest("New password and confirm password do not match");
                }

                var user = await _context.Users
                    .FirstOrDefaultAsync(u => u.Uid == email);

                if (user == null)
                {
                    return NotFound("Email not found");
                }

                user.Password = newPassword;

                await _context.SaveChangesAsync();

                return Ok("Password updated successfully");
            }
            catch (System.Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }

        // (Optional) keep your existing GET APIs
        [HttpGet]
        public async Task<ActionResult<IEnumerable<User>>> GetUsers()
        {
            return await _context.Users.ToListAsync();
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<User>> GetUser(string id)
        {
            var user = await _context.Users.FindAsync(id);

            if (user == null)
            {
                return NotFound();
            }

            return user;
        }
    }
}