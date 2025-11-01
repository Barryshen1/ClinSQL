with vent_items AS (
  SELECT ARRAY_AGG(itemid) AS itemids
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ventilation%'
     OR LOWER(label) LIKE '%ventilator%'
     OR LOWER(category) LIKE '%ventilation%'
),
vasop_items AS (
  SELECT ARRAY_AGG(itemid) AS itemids
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%norepinephrine%'
     OR LOWER(label) LIKE '%epinephrine%'
     OR LOWER(label) LIKE '%vasopressor%'
     OR LOWER(label) LIKE '%dopamine%'
     OR LOWER(label) LIKE '%phenylephrine%'
     OR LOWER(category) LIKE '%vasopressor%'
),
rrt_items AS (
  SELECT ARRAY_AGG(itemid) AS itemids
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%renal replacement%'
     OR LOWER(label) LIKE '%crrt%'
),

-- 2) Base population: female, age 71-81, with complications of care
base_population AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS death_flag,
    p.gender,
    p.anchor_age,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS in_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    -- complications of care: long_title contains 'complications' and 'care'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
        ON di.icd_code = ddi.icd_code
       AND di.icd_version = ddi.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(ddi.long_title) LIKE '%complications%care%'
    )
),

flags AS (
  SELECT
    b.hadm_id,
    CASE WHEN b.dischtime IS NOT NULL AND b.admittime IS NOT NULL THEN TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY) ELSE NULL END AS los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
        ON di.icd_code = ddi.icd_code
       AND di.icd_version = ddi.icd_version
      WHERE di.hadm_id = b.hadm_id
        AND LOWER(ddi.long_title) LIKE '%complications%care%'
    ) THEN 1 ELSE 0 END AS death_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      WHERE ce.hadm_id = b.hadm_id
        AND ce.charttime BETWEEN b.admittime AND b.dischtime
        AND ce.itemid IN UNNEST((SELECT itemids FROM vent_items))
    ) THEN 1 ELSE 0 END AS vent_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      WHERE ce.hadm_id = b.hadm_id
        AND ce.charttime BETWEEN b.admittime AND b.dischtime
        AND ce.itemid IN UNNEST((SELECT itemids FROM vasop_items))
    ) THEN 1 ELSE 0 END AS vasop_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      WHERE ce.hadm_id = b.hadm_id
        AND ce.charttime BETWEEN b.admittime AND b.dischtime
        AND ce.itemid IN UNNEST((SELECT itemids FROM rrt_items))
    ) THEN 1 ELSE 0 END AS rrt_flag
  FROM base_population AS b
),

per_admission AS (
  SELECT
    CASE WHEN b.in_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    b.hadm_id,
    b.subject_id,
    b.admittime,
    b.dischtime,
    fl.death_flag AS death_flag,
    fl.los_days AS los_days,
    fl.vent_flag AS vent_flag,
    fl.vasop_flag AS vasop_flag,
    fl.rrt_flag AS rrt_flag
  FROM base_population AS b
  LEFT JOIN flags AS fl
    ON fl.hadm_id = b.hadm_id
),

quartile_calc AS (
  SELECT
    icu_group,
    los_days,
    vent_flag,
    vasop_flag,
    rrt_flag,
    death_flag,
    NTILE(4) OVER (PARTITION BY icu_group ORDER BY los_days) AS los_quartile
  FROM per_admission
  WHERE los_days IS NOT NULL
),

aggregated AS (
  SELECT
    icu_group,
    los_quartile,
    COUNT(*) AS total,
    SUM(death_flag) AS deaths,
    SUM(vent_flag) AS vent_total,
    SUM(vasop_flag) AS vasop_total,
    SUM(rrt_flag) AS rrt_total
  FROM quartile_calc
  GROUP BY icu_group, los_quartile
),

rates AS (
  SELECT
    icu_group,
    los_quartile,
    total,
    deaths,
    SAFE_DIVIDE(deaths, total) AS mort_rate,
    vent_total,
    vasop_total,
    rrt_total,
    SAFE_DIVIDE(vent_total, total) AS vent_pct,
    SAFE_DIVIDE(vasop_total, total) AS vasop_pct,
    SAFE_DIVIDE(rrt_total, total) AS rrt_pct
  FROM aggregated
),

q1_rate AS (
  SELECT icu_group, mort_rate AS q1_rate
  FROM rates
  WHERE los_quartile = 1
)

SELECT
  r.icu_group,
  r.los_quartile,
  r.total,
  r.deaths,
  r.mort_rate,
  SAFE_DIVIDE(r.mort_rate, q.q1_rate) AS rr_vs_q1,
  r.vent_pct,
  r.vasop_pct,
  r.rrt_pct
FROM rates AS r
LEFT JOIN q1_rate AS q
  ON r.icu_group = q.icu_group
ORDER BY r.icu_group, r.los_quartile;