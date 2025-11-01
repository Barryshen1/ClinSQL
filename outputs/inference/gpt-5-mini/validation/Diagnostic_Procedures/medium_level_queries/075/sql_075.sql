WITH admissions_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- Identify admissions with ACS and label as primary vs secondary based on seq_num
acs_admissions AS (
  SELECT
    ac.hadm_id,
    CASE
      WHEN MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS acs_role
  FROM
    admissions_cohort ac
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  USING (hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    -- Text-based ACS identification (adjust to a definitive ICD list if available)
    LOWER(d.long_title) LIKE '%acute%'
    AND (
      LOWER(d.long_title) LIKE '%myocard%'
      OR LOWER(d.long_title) LIKE '%coronar%'
      OR LOWER(d.long_title) LIKE '%angina%'
    )
  GROUP BY
    ac.hadm_id
),

-- Count diagnostic procedures per admission by day relative to admission
-- Using procedures_icd + d_icd_procedures and text filters to approximate "diagnostic"
proc_events AS (
  SELECT
    p.hadm_id,
    -- admission-relative day (admission day = 1)
    DATE_DIFF(DATE(p.chartdate), DATE(a.admittime), DAY) + 1 AS day
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON
    p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  JOIN
    admissions_cohort a
  ON
    p.hadm_id = a.hadm_id
  WHERE
    p.chartdate IS NOT NULL
    -- Approximate diagnostic procedures by text matching; refine with explicit codes if available
    AND (
      LOWER(dp.long_title) LIKE '%diagnos%'
      OR LOWER(dp.long_title) LIKE '%imaging%'
      OR LOWER(dp.long_title) LIKE '%radiolog%'
      OR LOWER(dp.long_title) LIKE '%angiograph%'
      OR LOWER(dp.long_title) LIKE '%catheteriz%'
    )
),

-- Aggregate counts per admission in the two windows (1-3 and 4-7)
proc_counts_per_adm AS (
  SELECT
    hadm_id,
    SUM(CASE WHEN day BETWEEN 1 AND 3 THEN 1 ELSE 0 END) AS cnt_1_3,
    SUM(CASE WHEN day BETWEEN 4 AND 7 THEN 1 ELSE 0 END) AS cnt_4_7
  FROM
    proc_events
  GROUP BY
    hadm_id
),

-- Combine ACS admissions (only those with ACS) with procedure counts, ensuring zeros included
per_admission_counts AS (
  SELECT
    a.hadm_id,
    acs.acs_role,
    COALESCE(pc.cnt_1_3, 0) AS proc_count_1_3,
    COALESCE(pc.cnt_4_7, 0) AS proc_count_4_7
  FROM
    acs_admissions acs
  JOIN
    admissions_cohort a
  USING (hadm_id)
  LEFT JOIN
    proc_counts_per_adm pc
  USING (hadm_id)
),

-- Unpivot the two windows so each row is (hadm_id, acs_role, day_range, proc_count)
unpivoted AS (
  SELECT hadm_id, acs_role, '1-3' AS day_range, proc_count_1_3 AS proc_count
  FROM per_admission_counts
  UNION ALL
  SELECT hadm_id, acs_role, '4-7' AS day_range, proc_count_4_7 AS proc_count
  FROM per_admission_counts
)

-- Final: compute approximate percentiles p25/p50/p75 per (acs_role, day_range)
SELECT
  acs_role,
  day_range,
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS p50,
  quantiles[OFFSET(75)] AS p75
FROM (
  SELECT
    acs_role,
    day_range,
    APPROX_QUANTILES(proc_count, 100) AS quantiles
  FROM
    unpivoted
  GROUP BY
    acs_role,
    day_range
)
ORDER BY
  acs_role,
  day_range;