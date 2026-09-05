using Accident_Detection_Backend.Models;
using Microsoft.AspNetCore.Mvc;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Accident_Detection_Backend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ConfigureNodesController : ControllerBase
    {
        private readonly AppDbContext db;

        public ConfigureNodesController(AppDbContext context)
        {
            db = context;
        }

        // ================= SAVE CONFIGURATION =================
        // ✅ URL: api/ConfigureNodes/SaveConfiguration?weight=1500
        [HttpPost("SaveConfiguration")]
        public IActionResult SaveConfiguration([FromBody] List<Nodes> nodes, [FromQuery] double weight)
        {
            try
            {
                if (nodes == null || !nodes.Any())
                {
                    return BadRequest("No configuration data provided.");
                }

                int categoryId = nodes.First().Category_Id;

                // ✅ FIXED (DYNAMIC CATEGORY)
                var category = db.Categories.FirstOrDefault(c => c.Category_Id == categoryId);

                if (category != null)
                {
                    category.Weight = (decimal)weight;
                }

                // ================= EXISTING NODES =================
                var existingNodes = db.Nodes
                    .Where(n => n.Category_Id == categoryId)
                    .ToList();

                foreach (var payload in nodes)
                {
                    var node = existingNodes.FirstOrDefault(n =>
                        n.Node_Id == payload.Node_Id &&
                        n.Category_Id == payload.Category_Id);

                    if (node != null)
                    {
                        // 🔁 UPDATE
                        node.Node_Position = payload.Node_Position;
                        node.Force = payload.Force;
                    }
                    else
                    {
                        // 🆕 INSERT
                        db.Nodes.Add(new Nodes
                        {
                            Node_Id = payload.Node_Id,
                            Category_Id = payload.Category_Id,
                            Node_Position = payload.Node_Position,
                            Force = payload.Force
                        });
                    }
                }

                db.SaveChanges();

                return Ok("Nodes + Weight saved successfully.");
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }

        // ================= GET NODES =================
        [HttpGet("GetNodes")]
        public IActionResult GetNodes([FromQuery] int categoryId)
        {
            try
            {
                var nodes = db.Nodes
                    .Where(n => n.Category_Id == categoryId)
                    .Select(n => new
                    {
                        n.Node_Id,
                        n.Category_Id,
                        n.Node_Position,
                        n.Force
                    })
                    .ToList();

                // ✅ GET CATEGORY WEIGHT
                var category = db.Categories
                    .FirstOrDefault(c => c.Category_Id == categoryId);

                var result = new
                {
                    Nodes = nodes,
                    Weight = category != null ? category.Weight : 0
                };

                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, ex.Message);
            }
        }
    }
}
