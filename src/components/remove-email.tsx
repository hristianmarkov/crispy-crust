"use client";
import { useState, type FormEvent } from "react";
export function RemoveEmail() {
  const [state, setState] = useState<"idle" | "loading" | "success" | "error">(
    "idle",
  );
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setState("loading");
    const email = new FormData(e.currentTarget).get("email");
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, action: "remove" }),
      });
      setState(res.ok ? "success" : "error");
    } catch {
      setState("error");
    }
  }
  return (
    <form className="remove-email" onSubmit={submit}>
      <label htmlFor="remove-email">Email address to remove</label>
      <div>
        <input
          name="email"
          id="remove-email"
          type="email"
          autoComplete="email"
          required
          placeholder="you@yourkitchen.com"
        />
        <button className="button" disabled={state === "loading"}>
          {state === "loading" ? "Removing…" : "Remove my email"}
        </button>
      </div>
      <p role="status">
        {state === "success"
          ? "If that address was on the list, its record has been removed."
          : state === "error"
            ? "We couldn’t complete that request. Please wait a minute and try again."
            : ""}
      </p>
    </form>
  );
}
