import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { api, setToken, type User } from "./api";

type AuthState = {
  user: User | null;
  ready: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const existing = localStorage.getItem("vibe_token");
    if (!existing) {
      setReady(true);
      return;
    }
    api
      .me()
      .then((payload) => setUser(payload.user))
      .catch(() => setToken(null))
      .finally(() => setReady(true));
  }, []);

  const value = useMemo<AuthState>(
    () => ({
      user,
      ready,
      login: async (email, password) => {
        const payload = await api.login(email, password);
        setToken(payload.token);
        setUser(payload.user);
      },
      logout: async () => {
        try {
          await api.logout();
        } finally {
          setToken(null);
          setUser(null);
        }
      }
    }),
    [user, ready]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("AuthProvider missing");
  return ctx;
}
