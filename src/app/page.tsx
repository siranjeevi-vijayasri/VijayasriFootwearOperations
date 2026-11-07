const navigation = [
  { label: "Dashboard", icon: "▦", active: true },
  { label: "Products", icon: "◇" },
  { label: "Suppliers", icon: "♧" },
  { label: "Purchases", icon: "⇩" },
  { label: "Inventory", icon: "▤" },
  { label: "Sales & POS", icon: "▣" },
  { label: "Customers", icon: "♙" },
  { label: "Reports", icon: "▥" }
];

const metrics = [
  { label: "Today's sales", value: "₹0.00", note: "No transactions recorded", icon: "↗" },
  { label: "Gross profit", value: "₹0.00", note: "Based on completed sales", icon: "◈" },
  { label: "Stock on hand", value: "—", note: "Awaiting inventory setup", icon: "▤" },
  { label: "Low-stock items", value: "—", note: "Reorder alerts will appear here", icon: "!" }
];

export default function DashboardPage() {
  return (
    <main className="app-shell">
      <aside className="sidebar">
        <a className="brand" href="/" aria-label="Vijayasri Footwear Operations home">
          <span className="brand-mark">V</span>
          <span><strong>Vijayasri</strong><small>FOOTWEAR OPERATIONS</small></span>
        </a>
        <div className="workspace-label">WORKSPACE</div>
        <nav className="nav-list" aria-label="Main navigation">
          {navigation.map((item) => (
            <div className={item.active ? "nav-item active" : "nav-item disabled"} key={item.label}>
              <span className="nav-icon" aria-hidden="true">{item.icon}</span>
              <span>{item.label}</span>
              {!item.active && <span className="soon">Soon</span>}
            </div>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="store-avatar">VF</div>
          <div><strong>Vijayasri Footwear</strong><small>Retail workspace</small></div>
        </div>
      </aside>

      <section className="main-panel">
        <header className="topbar">
          <div className="breadcrumb">Workspace <span>/</span> Dashboard</div>
          <div className="topbar-right"><span className="environment"><i /> Development</span><div className="user-avatar">O</div></div>
        </header>

        <div className="page-content">
          <div className="page-heading">
            <div><p className="eyebrow">OVERVIEW</p><h1>Good day</h1><p className="subheading">Here&apos;s what&apos;s happening at your store.</p></div>
            <span className="date-label">Operations workspace</span>
          </div>

          <section className="metric-grid" aria-label="Business overview">
            {metrics.map((metric) => (
              <article className="metric-card" key={metric.label}>
                <div className="metric-top"><span>{metric.label}</span><span className="metric-icon">{metric.icon}</span></div>
                <strong className="metric-value">{metric.value}</strong>
                <p>{metric.note}</p>
              </article>
            ))}
          </section>

          <section className="content-grid">
            <article className="panel activity-panel">
              <div className="panel-heading"><div><h2>Recent activity</h2><p>Your latest store transactions and updates</p></div><span className="panel-tag">LIVE DATA PENDING</span></div>
              <div className="empty-state"><div className="empty-icon">↻</div><strong>Activity will show up here</strong><p>Once products, purchases and sales are connected, you&apos;ll see a live timeline of store activity.</p></div>
            </article>
            <article className="panel setup-panel">
              <div className="panel-heading"><div><h2>Getting started</h2><p>Set up your operations workspace</p></div></div>
              <ol className="setup-list">
                <li className="complete"><span>✓</span><div><strong>Project workspace created</strong><small>Dedicated repository established</small></div></li>
                <li><span>2</span><div><strong>Connect the operations database</strong><small>Create a separate Supabase project</small></div></li>
                <li><span>3</span><div><strong>Set up products and SKU variants</strong><small>Track each size and colour separately</small></div></li>
                <li><span>4</span><div><strong>Start recording stock movements</strong><small>Purchases, sales, returns and adjustments</small></div></li>
              </ol>
            </article>
          </section>

          <div className="notice"><span className="notice-icon">i</span><p><strong>Development foundation</strong> — This dashboard currently uses placeholder values. Live sales, inventory and profit figures will appear only after the database and transaction workflows are implemented and tested.</p></div>
          <footer>Vijayasri Footwear Operations <span>•</span> Foundation build</footer>
        </div>
      </section>
    </main>
  );
}
