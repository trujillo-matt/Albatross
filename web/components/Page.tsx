/** Phone-width column for players, a wider column for the admin dashboard on desktop. */
export default function Page({ wide = false, children }: { wide?: boolean; children: React.ReactNode }) {
  return <div className={`mx-auto w-full ${wide ? "max-w-5xl" : "max-w-xl"}`}>{children}</div>;
}
