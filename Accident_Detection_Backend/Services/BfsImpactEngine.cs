using System;
using System.Collections.Generic;
using System.Linq;
using AccidentDetectionAndAlertSystem.Configuration;
using Accident_Detection_Backend.Models;

namespace AccidentDetectionAndAlertSystem.Services
{
    public class BfsImpactEngine
    {
        private readonly CrashScalingConfig _config;

        public BfsImpactEngine(CrashScalingConfig config)
        {
            _config = config ?? new CrashScalingConfig();
        }

        /// <summary>
        /// Propagates scaled impact force through vehicle structural nodes using BFS graph traversal.
        /// </summary>
        public (double cabinForce, double cabinDamagePercent, Dictionary<int, double> nodeForces, Dictionary<int, double> deadEndForces)
            Propagate(List<NodeConnection> connections, Dictionary<int, double> absorption, int startNode, double initialForceN, bool isRollover)
        {
            var visited = new HashSet<int>();
            var nodeForces = new Dictionary<int, double>();
            var deadEndForces = new Dictionary<int, double>();

            var graph = connections.GroupBy(c => c.From_Node).ToDictionary(g => g.Key, g => g.ToList());
            var queue = new Queue<(int node, double force)>();

            queue.Enqueue((startNode, initialForceN));

            while (queue.Count > 0)
            {
                var (node, incoming) = queue.Dequeue();
                if (visited.Contains(node)) continue;
                visited.Add(node);

                nodeForces[node] = incoming;
                double absorb = absorption.TryGetValue(node, out var absVal) ? absVal : 0;
                double remaining = Math.Max(0, (incoming - absorb) * _config.EnergyAttenuationFactor);

                if (remaining <= 5) continue;
                if (!graph.ContainsKey(node)) continue;

                var outbound = graph[node];
                if (outbound == null || outbound.Count == 0) continue;

                foreach (var edge in outbound)
                {
                    if (!isRollover && edge.Is_Cabin_Deadend)
                    {
                        if (!deadEndForces.ContainsKey(node)) deadEndForces[node] = 0;
                        deadEndForces[node] += remaining;
                    }
                    else if (edge.To_Node != node && !visited.Contains(edge.To_Node))
                    {
                        double weight = (edge.Force_Weight.HasValue && edge.Force_Weight.Value > 0)
                            ? (double)edge.Force_Weight.Value
                            : (1.0 / outbound.Count);

                        queue.Enqueue((edge.To_Node, remaining * weight));
                    }
                }
            }

            double totalDeadEnd = deadEndForces.Values.Sum();
            double cabinForce;
            if (!isRollover && totalDeadEnd > 0)
            {
                cabinForce = totalDeadEnd;
            }
            else
            {
                cabinForce = nodeForces.ContainsKey(13)
                    ? nodeForces[13]
                    : (nodeForces.Any() ? nodeForces.Values.Max() * 0.35 : initialForceN * 0.25);
            }

            if (isRollover)
            {
                cabinForce *= _config.RolloverForceMultiplier;
            }

            double maxForce = Math.Max(initialForceN, nodeForces.Values.DefaultIfEmpty(initialForceN).Max());
            if (maxForce <= 0) maxForce = 1;

            double normalized = Math.Min(1.0, cabinForce / maxForce);
            double damage = Math.Pow(normalized, 1.6) * 100.0;
            if (isRollover) damage *= _config.RolloverDamageMultiplier;
            damage = Math.Max(1.0, Math.Min(100.0, damage));

            return (cabinForce, damage, nodeForces, deadEndForces);
        }

        public double PropagateForceToCabin(double realWorldForceN, Dictionary<int, double> nodeAbsorptionMap, int impactNode)
        {
            double absorbed = nodeAbsorptionMap.TryGetValue(impactNode, out var abs) ? abs : 0;
            double remaining = Math.Max(0, (realWorldForceN - absorbed) * _config.EnergyAttenuationFactor);
            return remaining;
        }

        public string CalculateAisScore(double cabinTransmittedForceN)
        {
            double occupantG = cabinTransmittedForceN / (70.0 * 9.81);
            if (occupantG >= 40.0 || cabinTransmittedForceN >= 27440)
                return "AIS 5-6 (Critical / Fatal)";
            if (occupantG >= 20.0 || cabinTransmittedForceN >= 13720)
                return "AIS 3-4 (Serious to Severe)";
            if (occupantG >= 10.0 || cabinTransmittedForceN >= 6860)
                return "AIS 2 (Moderate)";
            if (occupantG >= 4.0 || cabinTransmittedForceN >= 2744)
                return "AIS 1 (Minor)";
            return "AIS 0 (None / Safe)";
        }
    }
}
