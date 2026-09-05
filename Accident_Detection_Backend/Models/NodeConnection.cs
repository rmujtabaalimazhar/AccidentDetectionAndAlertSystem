// namespace Accident_Detection_Backend.Models
// {
//     using System;

//     public partial class NodeConnection
//     {
//         public int Connection_Id { get; set; }
//         public int From_Node { get; set; }
//         public int To_Node { get; set; }
//         public int Category_Id { get; set; }

//         public virtual Nodes Node { get; set; }
//         public virtual Nodes Node1 { get; set; }
//     }
// }

using System;
using System.ComponentModel.DataAnnotations; // 👈 Add this using statement
using System.ComponentModel.DataAnnotations.Schema;

namespace Accident_Detection_Backend.Models
{
    [Table("NodeConnections")] // 👈 Optional but good practice to map to the exact table name
    public partial class NodeConnection
    {
        [Key] // 👈 ADD THIS ATTRIBUTE
        public int Connection_Id { get; set; }
        
        public int From_Node { get; set; }
        public int To_Node { get; set; }
        public int Category_Id { get; set; }

        // Navigation properties
        [ForeignKey("From_Node, Category_Id")]
        public virtual Nodes? Node { get; set; }
        
        [ForeignKey("To_Node, Category_Id")]
        public virtual Nodes? Node1 { get; set; }
    }
}
