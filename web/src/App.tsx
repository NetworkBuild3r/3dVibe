import { Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./auth";
import { Layout } from "./components/Layout";
import { CurationPage } from "./pages/CurationPage";
import { GalleryPage } from "./pages/GalleryPage";
import { InvitesPage } from "./pages/InvitesPage";
import { LibrariesPage } from "./pages/LibrariesPage";
import { LoginPage } from "./pages/LoginPage";
import { ModelPage } from "./pages/ModelPage";
import { PrintersPage } from "./pages/PrintersPage";
import { PrintsPage } from "./pages/PrintsPage";
import { RedeemPage } from "./pages/RedeemPage";
import { UploadPage } from "./pages/UploadPage";

function Guard({ children }: { children: React.ReactNode }) {
  const { user, ready } = useAuth();
  if (!ready) {
    return <div className="grid min-h-screen place-items-center text-slate-400">Loading 3dvibe…</div>;
  }
  if (!user) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

function OwnerGuard({ children }: { children: React.ReactNode }) {
  const { user } = useAuth();
  if (!user?.can_invite) return <Navigate to="/" replace />;
  return <>{children}</>;
}

function UploadGuard({ children }: { children: React.ReactNode }) {
  const { user } = useAuth();
  if (!user?.can_upload) return <Navigate to="/" replace />;
  return <>{children}</>;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/invite/:token" element={<RedeemPage />} />
      <Route
        element={
          <Guard>
            <Layout />
          </Guard>
        }
      >
        <Route path="/" element={<GalleryPage />} />
        <Route path="/models/:id" element={<ModelPage />} />
        <Route path="/curation" element={<CurationPage />} />
        <Route path="/prints" element={<PrintsPage />} />
        <Route
          path="/printers"
          element={
            <OwnerGuard>
              <PrintersPage />
            </OwnerGuard>
          }
        />
        <Route
          path="/libraries"
          element={
            <OwnerGuard>
              <LibrariesPage />
            </OwnerGuard>
          }
        />
        <Route
          path="/invites"
          element={
            <OwnerGuard>
              <InvitesPage />
            </OwnerGuard>
          }
        />
        <Route
          path="/upload"
          element={
            <UploadGuard>
              <UploadPage />
            </UploadGuard>
          }
        />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
