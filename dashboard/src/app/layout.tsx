import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Sellwild Auction Dashboard',
  description: 'Real-time auction analytics powered by AWS Athena',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <head>
        <link
          href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="bg-gray-950 text-white min-h-screen">
        <nav className="border-b border-gray-800 bg-gray-900/80 backdrop-blur sticky top-0 z-50">
          <div className="max-w-[1400px] mx-auto px-6 h-14 flex items-center justify-between">
            <a href="/" className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-emerald-500 to-emerald-700 flex items-center justify-center font-bold text-sm">
                SW
              </div>
              <span className="font-semibold text-lg">Auction Dashboard</span>
            </a>
            <div className="flex items-center gap-6 text-sm text-gray-400">
              <a href="/" className="hover:text-white transition-colors">
                Overview
              </a>
              <a href="/auctions" className="hover:text-white transition-colors">
                Auctions
              </a>
              <span className="px-2 py-1 rounded bg-emerald-900/50 text-emerald-400 text-xs font-medium">
                Athena
              </span>
            </div>
          </div>
        </nav>
        <main className="max-w-[1400px] mx-auto px-6 py-8">{children}</main>
      </body>
    </html>
  );
}
