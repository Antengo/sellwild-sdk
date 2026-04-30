'use client';

interface StatsCardProps {
  label: string;
  value: string | number;
  detail?: string;
  color?: 'emerald' | 'blue' | 'amber' | 'red' | 'purple';
}

const colorMap = {
  emerald: 'from-emerald-500/20 to-emerald-500/5 border-emerald-500/30',
  blue: 'from-blue-500/20 to-blue-500/5 border-blue-500/30',
  amber: 'from-amber-500/20 to-amber-500/5 border-amber-500/30',
  red: 'from-red-500/20 to-red-500/5 border-red-500/30',
  purple: 'from-purple-500/20 to-purple-500/5 border-purple-500/30',
};

export function StatsCard({ label, value, detail, color = 'emerald' }: StatsCardProps) {
  return (
    <div
      className={`rounded-xl border bg-gradient-to-br p-5 ${colorMap[color]}`}
    >
      <p className="text-sm font-medium text-gray-400 mb-1">{label}</p>
      <p className="text-3xl font-bold text-white">{value}</p>
      {detail && (
        <p className="text-xs text-gray-500 mt-2">{detail}</p>
      )}
    </div>
  );
}
