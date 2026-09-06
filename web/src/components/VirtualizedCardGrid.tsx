import { useWindowVirtualizer } from "@tanstack/react-virtual";
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { ModelCard as ModelCardType } from "../api";
import { columnCount, gridMetrics, type GalleryDensity } from "../gallery";

export function VirtualizedCardGrid({
  models,
  density,
  renderCard
}: {
  models: ModelCardType[];
  density: GalleryDensity;
  renderCard: (model: ModelCardType) => ReactNode;
}) {
  const parentRef = useRef<HTMLDivElement | null>(null);
  const [width, setWidth] = useState(0);
  const [scrollMargin, setScrollMargin] = useState(0);

  useEffect(() => {
    const node = parentRef.current;
    if (!node) return;
    const sync = () => {
      setWidth(node.clientWidth);
      setScrollMargin(node.offsetTop);
    };
    sync();
    const observer = new ResizeObserver(sync);
    observer.observe(node);
    return () => observer.disconnect();
  }, [density, models.length]);

  const columns = columnCount(width, density);
  const { gap, estimateRow } = gridMetrics(density);
  const rowCount = Math.max(1, Math.ceil(models.length / columns));

  const virtualizer = useWindowVirtualizer({
    count: rowCount,
    estimateSize: () => estimateRow,
    overscan: 6,
    scrollMargin
  });

  return (
    <div
      ref={parentRef}
      className={density === "compact" ? "card-grid-host compact" : "card-grid-host"}
      style={{ height: virtualizer.getTotalSize() }}
    >
      {virtualizer.getVirtualItems().map((row) => {
        const start = row.index * columns;
        const items = models.slice(start, start + columns);
        return (
          <div
            key={row.key}
            data-index={row.index}
            ref={virtualizer.measureElement}
            className="absolute left-0 w-full"
            style={{
              transform: `translateY(${row.start - scrollMargin}px)`,
              display: "grid",
              gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`,
              gap
            }}
          >
            {items.map((model) => (
              <div key={model.id}>{renderCard(model)}</div>
            ))}
          </div>
        );
      })}
    </div>
  );
}
