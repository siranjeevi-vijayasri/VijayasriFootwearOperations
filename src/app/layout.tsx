import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Vijayasri Footwear | Operations",
  description: "Retail operations workspace for Vijayasri Footwear."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
