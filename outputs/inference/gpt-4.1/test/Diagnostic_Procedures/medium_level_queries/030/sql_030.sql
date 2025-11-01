WITH cohort AS (
  -- Step 1: Select admissions for females age 53–63 with upper GI bleeding, LOS 1–8 days
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM a.dischtime - a.admittime) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND EXTRACT(DAY FROM a.dischtime - a.admittime) BETWEEN 1 AND 8
    AND (
      -- Upper GI bleeding ICD codes
      d.icd_code IN ('K920', 'K921', 'K922', 'I850')
      OR (dd.long_title LIKE '%hemorrhage%' OR dd.long_title LIKE '%bleed%' OR dd.long_title LIKE '%hematemesis%' OR dd.long_title LIKE '%melena%')
      OR (d.icd_code LIKE 'K25%' OR d.icd_code LIKE 'K26%' OR d.icd_code LIKE 'K27%' OR d.icd_code LIKE 'K28%')
    )
),
diagnostic_procs AS (
  -- Step 2: For each admission, count unique diagnostic procedures
  SELECT
    c.hadm_id,
    c.los_days,
    COUNT(DISTINCT pr.icd_code) AS num_diag_procs
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON c.hadm_id = pr.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    -- Only diagnostic procedures
    LOWER(dp.long_title) LIKE '%diagnostic%'
    OR LOWER(dp.long_title) LIKE '%endoscopy%'
    OR LOWER(dp.long_title) LIKE '%imaging%'
    OR LOWER(dp.long_title) LIKE '%biopsy%'
    OR LOWER(dp.long_title) LIKE '%ultrasound%'
    OR LOWER(dp.long_title) LIKE '%ct%'
    OR LOWER(dp.long_title) LIKE '%mri%'
    OR LOWER(dp.long_title) LIKE '%x-ray%'
    OR LOWER(dp.long_title) LIKE '%esophagogastroduodenoscopy%'
    OR LOWER(dp.long_title) LIKE '%colonoscopy%'
    -- Add more keywords as needed for diagnostic procedures
    OR dp.icd_code IS NULL -- To count zero if no procedures
  GROUP BY
    c.hadm_id,
    c.los_days
),
diagnostic_counts AS (
  -- Step 3: Assign LOS group
  SELECT
    hadm_id,
    num_diag_procs,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_group
  FROM
    diagnostic_procs
  WHERE
    los_days BETWEEN 1 AND 8
)
-- Step 4: Calculate percentiles for each LOS group
SELECT
  los_group,
  APPROX_QUANTILES(num_diag_procs, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_diag_procs, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_diag_procs, 4)[OFFSET(3)] AS p75
FROM
  diagnostic_counts
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group
ORDER BY
  los_group;