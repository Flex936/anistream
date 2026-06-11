export function formatStatus(status: string | undefined): string {
  if (!status) return "UNKNOWN";
  return status.replace(/_/g, " ");
}

export function getCardStatusColor(status: string | undefined): string {
  switch (status) {
    case "RELEASING":
      return "text-green-400 border-green-400/20";
    case "FINISHED":
      return "text-sky-400 border-sky-400/20";
    case "CANCELLED":
      return "text-red-400 border-red-400/20";
    case "HIATUS":
      return "text-orange-400 border-orange-400/20";
    default:
      return "text-white border-border/50";
  }
}

export function getSidebarBadgeStyle(status: string | undefined): string {
  switch (status) {
    case "RELEASING":
      return "bg-green-400/20 text-green-400 border-green-400/30";
    case "FINISHED":
      return "bg-sky-400/20 text-sky-400 border-sky-400/30";
    case "CANCELLED":
      return "bg-red-400/20 text-red-400 border-red-400/30";
    case "HIATUS":
      return "bg-orange-400/20 text-orange-400 border-orange-400/30";
    default:
      return "bg-surface border-border text-muted";
  }
}
