export default function NotFound() {
  return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-gray-400 mb-2">404</h1>
        <p className="text-gray-500">Page not found</p>
        <a href="/" className="text-emerald-400 hover:text-emerald-300 text-sm mt-4 inline-block">
          Back to Dashboard
        </a>
      </div>
    </div>
  );
}
