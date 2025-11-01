WITH
-- 1) compute next admission time for each admission (to detect 30-day readmission)
admissions_with_next AS (
  SELECT
    a.*,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- 2) define cohort: male patients age 37-47 with an ICU stay and a procedure on or before ICU intime (post-op)
cohort_base AS (
  SELECT
    awn.subject_id,
    awn.hadm_id,
    awn.admittime,
    awn.dischtime,
    awn.hospital_expire_flag,
    awn.next_admittime,
    icu.intime AS icu_intime,
    p.anchor_age
  FROM
    admissions_with_next awn
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON awn.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON awn.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    -- require at least one procedure on or before ICU intime -> operational "postoperative" filter
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      WHERE pr.hadm_id = awn.hadm_id
        AND pr.chartdate IS NOT NULL
        AND DATE(icu.intime) >= pr.chartdate
    )
),

-- 3) medication counts in first 72 hours after admission
meds_per_adm AS (
  SELECT
    cb.subject_id,
    cb.hadm_id,
    cb.admittime,
    cb.dischtime,
    cb.hospital_expire_flag,
    cb.next_admittime,
    cb.icu_intime,
    cb.anchor_age,
    -- count distinct prescription drug identifiers overlapping the first 72 hours
    COALESCE(
      COUNT(DISTINCT LOWER(TRIM(COALESCE(p.drug, p.formulary_drug_cd)))), 
      0
    ) AS med_count
  FROM
    cohort_base cb
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON p.hadm_id = cb.hadm_id
      -- prescription overlaps the window [admittime, admittime + 72 hours)
      AND p.starttime IS NOT NULL
      AND p.starttime < TIMESTAMP_ADD(cb.admittime, INTERVAL 72 HOUR)
      AND (p.stoptime IS NULL OR p.stoptime > cb.admittime)
  GROUP BY
    cb.subject_id,
    cb.hadm_id,
    cb.admittime,
    cb.dischtime,
    cb.hospital_expire_flag,
    cb.next_admittime,
    cb.icu_intime,
    cb.anchor_age
),

-- 4) compute LOS days and readmit_30d flag, and assign quintiles by med_count
with_outcomes_and_quintile AS (
  SELECT
    m.*,
    SAFE_DIVIDE(TIMESTAMP_DIFF(m.dischtime, m.admittime, SECOND), 86400.0) AS los_days,
    CASE
      WHEN m.next_admittime IS NOT NULL
        AND TIMESTAMP_DIFF(m.next_admittime, m.dischtime, DAY) BETWEEN 0 AND 30 THEN 1
      ELSE 0
    END AS readmit_30d,
    NTILE(5) OVER (ORDER BY med_count) AS quintile
  FROM
    meds_per_adm m
),

-- 5) per-quintile aggregated metrics (use APPROX_QUANTILES directly instead of ARRAY_AGG + UNNEST)
quintile_summary AS (
  SELECT
    quintile,
    COUNT(*) AS n_admissions,
    -- med_count summary
    AVG(med_count) AS mean_med_count,
    -- approximate median med_count via APPROX_QUANTILES
    APPROX_QUANTILES(med_count, 100)[OFFSET(50)] AS median_med_count,
    -- med_count range per quintile for mapping
    MIN(med_count) AS min_med_count,
    MAX(med_count) AS max_med_count,
    -- LOS summaries
    AVG(los_days) AS mean_los_days,
    -- approximate median LOS
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    -- outcome rates
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS inhospital_mortality_rate,
    AVG(CAST(readmit_30d AS FLOAT64)) AS readmit_30d_rate
  FROM
    with_outcomes_and_quintile
  GROUP BY
    quintile
  ORDER BY
    quintile
),

-- 6) compute the "representative" 42-year-old med_count (median among anchor_age = 42)
median_medcount_age42 AS (
  SELECT
    -- if there are multiple admissions for age 42, we take the cohort median med_count among them
    APPROX_QUANTILES(med_count, 100)[OFFSET(50)] AS median_med_count_age42
  FROM with_outcomes_and_quintile w
  WHERE w.anchor_age = 42
),

-- 7) find which quintile that median_med_count_age42 falls into (use min/max ranges)
patient_quintile AS (
  SELECT
    m.median_med_count_age42,
    q.quintile,
    q.n_admissions,
    q.mean_med_count,
    q.median_med_count,
    q.min_med_count,
    q.max_med_count,
    q.mean_los_days,
    q.median_los_days,
    q.inhospital_mortality_rate,
    q.readmit_30d_rate
  FROM
    median_medcount_age42 m
    LEFT JOIN quintile_summary q
      ON m.median_med_count_age42 BETWEEN q.min_med_count AND q.max_med_count
)

-- Final output: per-quintile rows followed by a patient_estimate row
SELECT
  CAST(quintile AS STRING) AS report_type,
  quintile,
  n_admissions,
  ROUND(mean_med_count, 2) AS mean_med_count,
  CAST(median_med_count AS INT64) AS median_med_count,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(median_los_days, 2) AS median_los_days,
  ROUND(inhospital_mortality_rate, 4) AS inhospital_mortality_rate,
  ROUND(readmit_30d_rate, 4) AS readmit_30d_rate
FROM
  quintile_summary

UNION ALL

SELECT
  'patient_estimate' AS report_type,
  pq.quintile,
  pq.n_admissions,
  ROUND(pq.mean_med_count, 2) AS mean_med_count,
  CAST(pq.median_med_count AS INT64) AS median_med_count,
  ROUND(pq.mean_los_days, 2) AS mean_los_days,
  ROUND(pq.median_los_days, 2) AS median_los_days,
  ROUND(pq.inhospital_mortality_rate, 4) AS inhospital_mortality_rate,
  ROUND(pq.readmit_30d_rate, 4) AS readmit_30d_rate
FROM
  patient_quintile pq

ORDER BY
  report_type DESC,
  quintile;