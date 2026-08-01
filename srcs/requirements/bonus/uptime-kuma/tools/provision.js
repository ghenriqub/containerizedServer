/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   provision.js                                       :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/08/01 21:18:22 by ghenriqu          #+#    #+#             */
/*   Updated: 2026/08/01 21:19:10 by ghenriqu         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

"use strict";

const fs = require("fs");
const { io } = require("socket.io-client");

const URL = process.env.KUMA_URL || "http://127.0.0.1:3001";
const ADMIN_USER = process.env.KUMA_ADMIN_USER || "boss";
const DOMAIN_NAME = process.env.DOMAIN_NAME || "localhost";
const SECRET_FILE = process.env.KUMA_PASSWORD_FILE || "/run/secrets/kuma_password";
const MONITORS_FILE = process.env.KUMA_MONITORS_FILE || "/app/extra/monitors.json";

const PASSWORD = fs.readFileSync(SECRET_FILE, "utf8").trim();

const MONITORS = JSON.parse(
    fs.readFileSync(MONITORS_FILE, "utf8").replace(/__DOMAIN__/g, DOMAIN_NAME)
);

const DEFAULTS = {
    type: "http",
    active: true,
    interval: 60,
    retryInterval: 60,
    resendInterval: 0,
    maxretries: 1,
    timeout: 30,
    method: "GET",
    maxredirects: 10,
    accepted_statuscodes: ["200-299"],
    ignoreTls: false,
    upsideDown: false,
    expiryNotification: false,
    conditions: [],
    kafkaProducerBrokers: [],
    rabbitmqNodes: [],
    notificationIDList: {},
};

function call(socket, event, ...args) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(
            () => reject(new Error(`timeout waiting for ack on "${event}"`)),
            15000
        );
        socket.emit(event, ...args, (res) => {
            clearTimeout(timer);
            resolve(res);
        });
    });
}

function waitForConnection(socket, graceMs) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(
            () => reject(new Error(`cannot reach Uptime Kuma at ${URL}`)),
            graceMs
        );
        socket.once("connect", () => {
            clearTimeout(timer);
            resolve();
        });
        socket.on("connect_error", (e) => console.log(`[provision] waiting: ${e.message}`));
    });
}

(async () => {
    const socket = io(URL, {
        transports: ["websocket"],
        reconnection: true,
        reconnectionDelay: 2000,
        reconnectionAttempts: Infinity,
    });

    const existing = new Set();
    socket.on("monitorList", (list) => {
        for (const id of Object.keys(list || {})) {
            existing.add(list[id].name);
        }
    });

    try {
        await waitForConnection(socket, 120000);
        console.log("[provision] connected");

        if (await call(socket, "needSetup")) {
            const res = await call(socket, "setup", ADMIN_USER, PASSWORD);
            if (!res.ok) {
                throw new Error(`setup rejected: ${res.msg}`);
            }
            console.log(`[provision] admin account "${ADMIN_USER}" created`);
        } else {
            console.log("[provision] admin account already exists, skipping setup");
        }

        const login = await call(socket, "login", {
            username: ADMIN_USER,
            password: PASSWORD,
            token: "",
        });
        if (!login.ok) {
            throw new Error(`login failed: ${login.msg || "wrong credentials"}`);
        }

        // Give the monitorList push a moment to arrive before we diff against it.
        await call(socket, "getMonitorList");
        await new Promise((r) => setTimeout(r, 1000));

        let added = 0;
        for (const monitor of MONITORS) {
            if (existing.has(monitor.name)) {
                console.log(`[provision] exists: ${monitor.name}`);
                continue;
            }
            const res = await call(socket, "add", { ...DEFAULTS, ...monitor });
            if (res.ok) {
                added++;
                console.log(`[provision] added:  ${monitor.name}`);
            } else {
                console.error(`[provision] FAILED: ${monitor.name} -> ${res.msg}`);
            }
        }

        console.log(`[provision] done (${added} monitor(s) created)`);
        socket.close();
        process.exit(0);
    } catch (e) {
        console.error(`[provision] ERROR: ${e.message}`);
        socket.close();
        process.exit(1);
    }
})();
