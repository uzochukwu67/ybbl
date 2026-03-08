import { Box, Text } from "@chakra-ui/react";
import { useMemo } from "react";
import { curvePoints, formatUnits } from "lib/starknetUtils";

interface Props {
  curveK: bigint;
  maxSupply: bigint;
  currentSupply: bigint;
  gradThreshold: bigint;
  reserve: bigint;
  width?: number;
  height?: number;
}

export const BondingCurveChart = ({
  curveK,
  maxSupply,
  currentSupply,
  gradThreshold,
  reserve,
  width = 600,
  height = 220,
}: Props) => {
  const pad = { t: 16, r: 16, b: 36, l: 56 };
  const W = width - pad.l - pad.r;
  const H = height - pad.t - pad.b;

  const points = useMemo(
    () => curvePoints(curveK, maxSupply === 0n ? 1_000_000_000n : maxSupply, currentSupply, 80),
    [curveK, maxSupply, currentSupply]
  );

  if (points.length < 2) return null;

  const maxPrice = Math.max(...points.map((p) => p.price), 1);
  const maxSup = points[points.length - 1].supply || 1;

  const toX = (s: number) => (s / maxSup) * W;
  const toY = (p: number) => H - (p / maxPrice) * H;

  const pathData = points
    .map((p, i) => `${i === 0 ? "M" : "L"} ${toX(p.supply).toFixed(1)} ${toY(p.price).toFixed(1)}`)
    .join(" ");

  // Area under sold portion
  const soldPoints = points.filter((p) => p.sold);
  const soldArea =
    soldPoints.length > 1
      ? [
          `M ${toX(soldPoints[0].supply).toFixed(1)} ${H}`,
          ...soldPoints.map((p) => `L ${toX(p.supply).toFixed(1)} ${toY(p.price).toFixed(1)}`),
          `L ${toX(soldPoints[soldPoints.length - 1].supply).toFixed(1)} ${H}`,
          "Z",
        ].join(" ")
      : "";

  // Graduation line x position
  const gradSupply = maxSup; // graduation is by reserve not supply, so mark at current
  const reservePct = gradThreshold > 0n ? Number((reserve * BigInt(maxSup)) / gradThreshold) : 0;
  const gradX = Math.min(toX(reservePct), W);

  // Y-axis labels (0, mid, max price)
  const yLabels = [
    { y: H, val: "0" },
    { y: H / 2, val: formatUnits((BigInt(Math.floor(maxPrice / 2))), 0).split(".")[0] },
    { y: 0, val: formatUnits(BigInt(Math.floor(maxPrice)), 0).split(".")[0] },
  ];

  return (
    <Box>
      <Text fontSize="xs" color="dark.300" mb={2}>
        Price curve · spot price vs supply sold
      </Text>
      <Box overflowX="auto">
        <svg
          width={width}
          height={height}
          viewBox={`0 0 ${width} ${height}`}
          style={{ display: "block", maxWidth: "100%" }}
        >
          <g transform={`translate(${pad.l},${pad.t})`}>
            {/* Grid lines */}
            {[0, 0.25, 0.5, 0.75, 1].map((f) => (
              <line
                key={f}
                x1={0}
                y1={H * f}
                x2={W}
                y2={H * f}
                stroke="#28282f"
                strokeWidth={1}
              />
            ))}

            {/* Sold area */}
            {soldArea && <path d={soldArea} className="curve-area-sold" />}

            {/* Full area */}
            <path
              d={`${pathData} L ${W} ${H} L 0 ${H} Z`}
              className="curve-area-unsold"
            />

            {/* Curve line */}
            <path d={pathData} className="curve-line" />

            {/* Graduation progress line */}
            {gradThreshold > 0n && (
              <line
                x1={gradX}
                y1={0}
                x2={gradX}
                y2={H}
                className="curve-grad-line"
              />
            )}

            {/* Y-axis labels */}
            {yLabels.map((l) => (
              <text
                key={l.y}
                x={-8}
                y={l.y + 4}
                textAnchor="end"
                fontSize={10}
                fill="#888"
              >
                {l.val}
              </text>
            ))}

            {/* X-axis labels */}
            <text x={0} y={H + 20} fontSize={10} fill="#888">0</text>
            <text x={W / 2} y={H + 20} textAnchor="middle" fontSize={10} fill="#888">
              Supply
            </text>
            <text x={W} y={H + 20} textAnchor="end" fontSize={10} fill="#888">
              {formatUnits(maxSupply === 0n ? 1_000_000_000n : maxSupply, 0).split(".")[0]}
            </text>
          </g>
        </svg>
      </Box>
    </Box>
  );
};
