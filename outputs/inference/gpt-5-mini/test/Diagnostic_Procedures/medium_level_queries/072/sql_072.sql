WITH
-- identify admissions for female patients age 52-62
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- identify which admissions have acute pancreatitis and whether it's primary (seq_num = 1)
ap_diagnoses AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute pancreatitis%' THEN 1 ELSE 0 END) AS has_ap,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute pancreatitis%' AND d.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    d.hadm_id
),

-- cohort: admissions meeting gender/age AND having acute pancreatitis (primary or secondary)
cohort AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    CASE WHEN ap.is_primary = 1 THEN 'primary' ELSE 'secondary' END AS ap_role
  FROM
    female_admissions fa
    JOIN ap_diagnoses ap
      ON fa.hadm_id = ap.hadm_id
  WHERE
    ap.has_ap = 1
),

-- diagnostic HCPCS events: select HCPCS events whose descriptions match diagnostic/imaging keywords
diag_hcpcs_events AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.chartdate,
    h.hcpcs_cd,
    COALESCE(h.short_description, '') || ' ' || COALESCE(d.long_description, '') AS description
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    -- basic safety: limit to events that have a hadm_id
    h.hadm_id IS NOT NULL
    -- keyword-based diagnostic/imaging filter (case-insensitive)
    AND REGEXP_CONTAINS(
      LOWER(COALESCE(h.short_description, '') || ' ' || COALESCE(d.long_description, '')),
      r'\b(ct|mri|ultrasound|ultrasonography|x-?ray|radiol|echocardi|ecg|ekg|angiograph|endoscop|colonoscopy|laparoscopy)\b'
    )
),

-- join cohort to events, compute day number relative to admission and bin into 1-4 or 5-8
events_with_days AS (
  SELECT
    c.hadm_id,
    c.ap_role,
    e.chartdate,
    DATE_DIFF(e.chartdate, DATE(c.admittime), DAY) + 1 AS day_number
  FROM
    cohort c
    JOIN diag_hcpcs_events e
      ON c.hadm_id = e.hadm_id
  WHERE
    -- only consider events in days 1 through 8
    DATE_DIFF(e.chartdate, DATE(c.admittime), DAY) + 1 BETWEEN 1 AND 8
),

-- aggregate counts per admission and period (1-4 vs 5-8)
events_counts AS (
  SELECT
    hadm_id,
    CASE WHEN day_number BETWEEN 1 AND 4 THEN '1-4' WHEN day_number BETWEEN 5 AND 8 THEN '5-8' END AS period,
    COUNT(*) AS num_diag_procs
  FROM
    events_with_days
  GROUP BY
    hadm_id, period
),

-- ensure every (hadm_id, period) pair exists so admissions with zero events are included
periods AS (
  SELECT '1-4' AS period UNION ALL SELECT '5-8'
),

hadm_periods AS (
  SELECT
    c.hadm_id,
    c.ap_role,
    p.period
  FROM
    cohort c
    CROSS JOIN periods p
),

-- left-join counts to get zero for missing combos
hadm_period_counts AS (
  SELECT
    hp.hadm_id,
    hp.ap_role,
    hp.period,
    COALESCE(ec.num_diag_procs, 0) AS num_diag_procs
  FROM
    hadm_periods hp
    LEFT JOIN events_counts ec
      ON hp.hadm_id = ec.hadm_id AND hp.period = ec.period
)

-- final aggregation: mean, min, max diagnostic procedures per admission stratified by primary/secondary and period
SELECT
  ap_role AS pancreatitis_role,
  period,
  ROUND(AVG(num_diag_procs), 3) AS mean_diag_procs_per_admission,
  MIN(num_diag_procs) AS min_diag_procs_per_admission,
  MAX(num_diag_procs) AS max_diag_procs_per_admission,
  COUNT(*) AS admissions_count
FROM
  hadm_period_counts
GROUP BY
  ap_role, period
ORDER BY
  ap_role DESC, period;