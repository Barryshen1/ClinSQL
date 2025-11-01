WITH base_admissions AS (
  -- 1) Cohort: male patients aged 68-78
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

labs_72h AS (
  -- 2) All six labs in the first 72h, with numeric values
  SELECT
    b.hadm_id,
    li.label AS lab_name,
    le.valuenum,
    le.flag
  FROM
    base_admissions b
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON b.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE
    le.charttime BETWEEN b.admittime AND TIMESTAMP_ADD(b.admittime, INTERVAL 72 HOUR)
    AND li.label IN (
      'Creatinine',
      'Potassium',
      'Platelets',
      'Hemoglobin',
      'Whole blood Potassium',
      'White Blood Cells'
    )
    AND le.valuenum IS NOT NULL
),

instabilities AS (
  -- 3) Compute per‐lab instability per admission
  SELECT
    hadm_id,
    lab_name,
    MAX(valuenum) - MIN(valuenum) AS instability
  FROM
    labs_72h
  GROUP BY
    hadm_id,
    lab_name
),

patient_scores AS (
  -- 4) Sum instabilities across the six labs
  SELECT
    hadm_id,
    SUM(instability) AS instability_score
  FROM
    instabilities
  GROUP BY
    hadm_id
),

score_with_pct AS (
  -- 5) Compute 90th percentile across all scores
  SELECT
    *,
    PERCENTILE_CONT(instability_score, 0.9) OVER () AS p90
  FROM
    patient_scores
),

top_tier AS (
  -- 6) Identify top-tier admissions
  SELECT
    p.hadm_id
  FROM
    score_with_pct p
  WHERE
    p.instability_score >= p.p90
),

-- 7a) Summarize top-tier outcomes & lab-critical rates
top_tier_stats AS (
  SELECT
    COUNT(*) AS n_top,
    AVG(b.los_days) AS avg_los_top,
    AVG(b.hospital_expire_flag) AS mortality_rate_top
  FROM
    top_tier t
  JOIN
    base_admissions b
    ON t.hadm_id = b.hadm_id
),

top_tier_lab_flags AS (
  -- Critical counts & totals for each lab in top-tier
  SELECT
    l.lab_name,
    COUNTIF(l.flag = 'abnormal') AS n_crit_top,
    COUNT(*) AS n_total_top
  FROM
    labs_72h l
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM top_tier)
  GROUP BY
    l.lab_name
),

-- 7b) Summarize overall lab-critical rates in the same male 68-78 cohort
all_lab_flags AS (
  SELECT
    lab_name,
    COUNTIF(flag = 'abnormal') AS n_crit_all,
    COUNT(*) AS n_total_all
  FROM
    labs_72h
  GROUP BY
    lab_name
)

-- 8) Final assembly
SELECT
  -- Top-tier summary
  s.n_top,
  s.avg_los_top,
  s.mortality_rate_top,
  -- Lab-by-lab comparison
  tl.lab_name,
  SAFE_DIVIDE(tl.n_crit_top, tl.n_total_top) AS crit_rate_top,
  SAFE_DIVIDE(al.n_crit_all, al.n_total_all) AS crit_rate_all
FROM
  top_tier_stats s
CROSS JOIN
  top_tier_lab_flags tl
JOIN
  all_lab_flags al
  ON tl.lab_name = al.lab_name
ORDER BY
  tl.lab_name;