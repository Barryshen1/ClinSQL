WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    i.stay_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
),

mech_vent AS (
  SELECT
    stay_id,
    MAX(1) AS mech_vent_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid = 225792
  GROUP BY stay_id
),

vasopressors AS (
  SELECT
    stay_id,
    MAX(1) AS vasopressor_flag
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (221906, 222315, 221289)
  GROUP BY stay_id
),

rrt AS (
  SELECT
    stay_id,
    MAX(1) AS rrt_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid = 227524
  GROUP BY stay_id
),

interventions AS (
  SELECT
    c.*,
    COALESCE(m.mech_vent_flag, 0) AS mech_vent_flag,
    COALESCE(v.vasopressor_flag, 0) AS vasopressor_flag,
    COALESCE(r.rrt_flag, 0) AS rrt_flag
  FROM cohort c
  LEFT JOIN mech_vent m ON c.stay_id = m.stay_id
  LEFT JOIN vasopressors v ON c.stay_id = v.stay_id
  LEFT JOIN rrt r ON c.stay_id = r.stay_id
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM interventions
),

base_agg AS (
  SELECT
    is_icu,
    los_quartile,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    SUM(mech_vent_flag) AS mech_vent,
    SUM(vasopressor_flag) AS vasopressors,
    SUM(rrt_flag) AS rrt
  FROM quartiles
  GROUP BY is_icu, los_quartile
),

q1_mortality AS (
  SELECT
    is_icu,
    deaths / n AS q1_mortality
  FROM base_agg
  WHERE los_quartile = 1
)

SELECT
  b.is_icu,
  b.los_quartile,
  b.deaths / b.n AS mortality_rate,
  (b.deaths / b.n) - q.q1_mortality AS abs_diff_q1,
  ((b.deaths / b.n) - q.q1_mortality) / q.q1_mortality AS rel_diff_q1,
  (b.mech_vent / b.n) * 100 AS mech_vent_pct,
  (b.vasopressors / b.n) * 100 AS vasopressors_pct,
  (b.rrt / b.n) * 100 AS rrt_pct
FROM base_agg b
JOIN q1_mortality q ON b.is_icu = q.is_icu
ORDER BY b.is_icu, b.los_quartile;