using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Accident_Detection_Backend.Models
{
    [Table("NodeConnections")]
    public partial class NodeConnection
    {
        [Key]
        [Column("Connection_Id")]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Connection_Id { get; set; }

        [Column("From_Node")]
        [Required]
        public int From_Node { get; set; }

        [Column("To_Node")]
        [Required]
        public int To_Node { get; set; }

        [Column("Category_Id")]
        [Required]
        public int Category_Id { get; set; }

        [Column("Force_Weight", TypeName = "decimal(3,2)")]
        public decimal? Force_Weight { get; set; }

        [Column("Is_Cabin_Deadend")]
        public bool Is_Cabin_Deadend { get; set; } = false;

        // ================= NAVIGATION PROPERTIES =================

        [JsonIgnore]
        [ForeignKey(nameof(Category_Id))]
        public virtual Category? Category { get; set; }

        [JsonIgnore]
        [ForeignKey($"{nameof(From_Node)}, {nameof(Category_Id)}")]
        public virtual Nodes? FromNode { get; set; }

        [JsonIgnore]
        [ForeignKey($"{nameof(To_Node)}, {nameof(Category_Id)}")]
        public virtual Nodes? ToNode { get; set; }
    }
}
