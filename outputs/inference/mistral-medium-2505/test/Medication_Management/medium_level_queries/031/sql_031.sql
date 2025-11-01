WITH
-- Define our target population: male patients 53-63 with diabetes and heart failure
target_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hospital_expire_flag = 0
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = p.subject_id
        AND diag.hadm_id = a.hadm_id
        AND diag.icd_code LIKE 'E11%'  -- Diabetes
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = p.subject_id
        AND diag.hadm_id = a.hadm_id
        AND diag.icd_code LIKE 'I50%'  -- Heart failure
    )
),

-- Identify GLP-1 RA prescriptions
glp1_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    drug,
    route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    (LOWER(drug) LIKE '%glp-1%'
     OR LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%semaglutide%')
    AND (LOWER(route) LIKE '%inject%'
         OR LOWER(route) LIKE '%subcutaneous%'
         OR LOWER(route) LIKE '%sc%')
),

-- Calculate time windows for each admission
time_windows AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR) AS first_24h_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AS final_12h_start
  FROM
    target_patients
),

-- Classify prescriptions by timing
prescription_timing AS (
  SELECT
    tp.hadm_id,
    CASE
      WHEN gp.starttime BETWEEN tw.admittime AND tw.first_24h_end THEN 'first_24h'
      WHEN gp.starttime BETWEEN tw.final_12h_start AND tw.dischtime THEN 'final_12h'
      ELSE 'other'
    END AS timing_category
  FROM
    target_patients tp
  JOIN
    time_windows tw ON tp.hadm_id = tw.hadm_id
  LEFT JOIN
    glp1_prescriptions gp
    ON tp.subject_id = gp.subject_id AND tp.hadm_id = gp.hadm_id
  WHERE
    gp.hadm_id IS NOT NULL
),

-- Count patients in each category
timing_counts AS (
  SELECT
    timing_category,
    COUNT(DISTINCT hadm_id) AS patient_count
  FROM
    prescription_timing
  GROUP BY
    timing_category
),

-- Get total number of target patients
total_patients AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_count
  FROM
    target_patients
)

-- Calculate percentages
SELECT
  tc.timing_category,
  tc.patient_count,
  ROUND((tc.patient_count / tp.total_count) * 100, 2) AS percentage
FROM
  timing_counts tc
CROSS JOIN
  total_patients tp
WHERE
  tc.timing_category IN ('first_24h', 'final_12h')
ORDER BY
  tc.timing_category;