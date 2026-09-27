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
    public class FamilyMembersController : ControllerBase
    {
        private readonly AppDbContext _context;

        public FamilyMembersController(AppDbContext context)
        {
            _context = context;
        }

        // ================= GET USER'S FAMILY MEMBERS / GUARDIANS =================
        // GET: api/FamilyMembers?uid=user@example.com
        [HttpGet]
        public async Task<IActionResult> GetFamilyMembers([FromQuery] string uid)
        {
            if (string.IsNullOrWhiteSpace(uid))
                return BadRequest("User ID is required.");

            try
            {
                var members = await _context.FamilyMembers
                    .Where(f => f.Uid == uid)
                    .Select(f => new
                    {
                        f.Family_Id,
                        f.Uid,
                        f.Guardian_Id,
                        f.Relationship,
                        GuardianName = _context.Users
                            .Where(u => u.Uid == f.Guardian_Id)
                            .Select(u => u.Name)
                            .FirstOrDefault() ?? f.Guardian_Id,
                        GuardianContact = _context.Users
                            .Where(u => u.Uid == f.Guardian_Id)
                            .Select(u => u.Contact_No)
                            .FirstOrDefault() ?? ""
                    })
                    .ToListAsync();

                return Ok(members);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= ADD FAMILY MEMBER / GUARDIAN =================
        // POST: api/FamilyMembers/Add
        public class AddFamilyMemberRequest
        {
            public string Uid { get; set; } = null!;
            public string GuardianId { get; set; } = null!;
            public string Relationship { get; set; } = null!;
        }

        [HttpPost("Add")]
        public async Task<IActionResult> AddFamilyMember([FromBody] AddFamilyMemberRequest request)
        {
            if (request == null || string.IsNullOrWhiteSpace(request.Uid) || string.IsNullOrWhiteSpace(request.GuardianId) || string.IsNullOrWhiteSpace(request.Relationship))
                return BadRequest(new { message = "All fields (Uid, GuardianId, Relationship) are required." });

            string uid = request.Uid.Trim();
            string guardianId = request.GuardianId.Trim();
            string relationship = request.Relationship.Trim();

            if (uid.Equals(guardianId, StringComparison.OrdinalIgnoreCase))
                return BadRequest(new { message = "You cannot add yourself as a guardian." });

            try
            {
                // Verify user exists
                var userExists = await _context.Users.AnyAsync(u => u.Uid == uid);
                if (!userExists)
                    return NotFound(new { message = "User not found." });

                // Verify guardian exists
                var guardianUser = await _context.Users.FirstOrDefaultAsync(u => u.Uid == guardianId);
                if (guardianUser == null)
                    return NotFound(new { message = $"No registered user found with ID '{guardianId}'." });

                // Check if already added
                var alreadyExists = await _context.FamilyMembers.AnyAsync(f => f.Uid == uid && f.Guardian_Id == guardianId);
                if (alreadyExists)
                    return Conflict(new { message = "This guardian is already added." });

                var familyMember = new FamilyMembers
                {
                    Uid = uid,
                    Guardian_Id = guardianId,
                    Relationship = relationship
                };

                _context.FamilyMembers.Add(familyMember);
                await _context.SaveChangesAsync();

                return Ok(new
                {
                    message = "Guardian added successfully.",
                    familyId = familyMember.Family_Id,
                    guardianName = guardianUser.Name,
                    guardianId = guardianUser.Uid,
                    relationship
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= REMOVE FAMILY MEMBER / GUARDIAN =================
        // DELETE: api/FamilyMembers/Remove?uid=user@example.com&guardianId=guardian@example.com
        [HttpDelete("Remove")]
        public async Task<IActionResult> RemoveFamilyMember([FromQuery] string uid, [FromQuery] string guardianId)
        {
            if (string.IsNullOrWhiteSpace(uid) || string.IsNullOrWhiteSpace(guardianId))
                return BadRequest(new { message = "Both uid and guardianId are required." });

            try
            {
                var record = await _context.FamilyMembers
                    .FirstOrDefaultAsync(f => f.Uid == uid.Trim() && f.Guardian_Id == guardianId.Trim());

                if (record == null)
                    return NotFound(new { message = "Family member record not found." });

                _context.FamilyMembers.Remove(record);
                await _context.SaveChangesAsync();

                return Ok(new { message = "Guardian removed successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // ================= SEARCH USERS BY ID / NAME =================
        // GET: api/FamilyMembers/Search?query=john
        [HttpGet("Search")]
        public async Task<IActionResult> SearchUsers([FromQuery] string query)
        {
            if (string.IsNullOrWhiteSpace(query))
                return Ok(new List<object>());

            try
            {
                string q = query.Trim().ToLower();
                var results = await _context.Users
                    .Where(u => u.Uid.ToLower().Contains(q) || u.Name.ToLower().Contains(q))
                    .Take(10)
                    .Select(u => new
                    {
                        u.Uid,
                        u.Name,
                        u.Contact_No
                    })
                    .ToListAsync();

                return Ok(results);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }
    }
}
