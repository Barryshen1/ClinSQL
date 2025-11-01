MAX(CASE WHEN g.starttime >= c.admittime AND g.starttime < c.admittime + INTERVAL '72 HOUR' THEN 1 ELSE 0 END) AS any_glp1_72h,
MAX(CASE WHEN g.starttime >= c.dischtime - INTERVAL '24 HOUR' AND g.starttime <= c.dischtime THEN 1 ELSE 0 END) AS any_glp1_24h,
MAX(CASE WHEN g.starttime >= c.admittime AND g.starttime < c.admittime + INTERVAL '72 HOUR' THEN 1 ELSE 0 END) AS init_72h,
MAX(CASE WHEN g.starttime >= c.dischtime - INTERVAL '24 HOUR' AND g.starttime <= c.dischtime
         AND NOT (g.starttime >= c.admittime AND g.starttime < c.admittime + INTERVAL '72 HOUR') THEN 1 ELSE 0 END) AS init_24h;