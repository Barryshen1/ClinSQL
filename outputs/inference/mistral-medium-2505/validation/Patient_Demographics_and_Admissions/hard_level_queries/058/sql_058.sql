WITH
-- Get all admissions for our target population
target_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.icd_code,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Get next admission for each patient
    LEAD(a.hadm_id) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_hadm_id,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE '%EMERGENCY%'
    AND d.icd_code IN ('K920', 'K921', 'K922') -- Lower GI bleeding ICD-10 codes
    AND a.hospital_expire_flag = 0 -- Exclude patients who died during hospitalization
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    CASE
      WHEN next_hadm_id IS NOT NULL
      AND TIMESTAMP_DIFF(next_admittime, dischtime, DAY) BETWEEN 1 AND 30
      THEN 1
      ELSE 0
    END AS is_readmitted_30d
  FROM
    target_admissions
),

-- Aggregate results
results AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients,
    SUM(is_readmitted_30d) AS readmitted_patients,
    COUNT(DISTINCT CASE WHEN los_days > 6 THEN subject_id END) AS los_gt_6_patients,
    COUNT(DISTINCT CASE WHEN is_readmitted_30d = 1 AND los_days > 6 THEN subject_id END) AS readmitted_los_gt_6_patients
  FROM
    readmissions
),

-- Calculate median LOS for readmitted vs not readmitted
los_stats AS (
  SELECT
    is_readmitted_30d,
    PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY is_readmitted_30d) AS median_los
  FROM
    readmissions
  GROUP BY
    is_readmitted_30d, los_days
)

-- Final output
SELECT
  r.readmitted_patients / r.total_patients AS readmission_rate_30d,
  MAX(CASE WHEN l.is_readmitted_30d = 1 THEN l.median_los ELSE NULL END) AS median_los_readmitted,
  MAX(CASE WHEN l.is_readmitted_30d = 0 THEN l.median_los ELSE NULL END) AS median_los_not_readmitted,
  r.los_gt_6_patients / r.total_patients AS percent_los_gt_6_days,
  r.readmitted_los_gt_6_patients / NULLIF(r.readmitted_patients, 0) AS percent_readmitted_los_gt_6_days
FROM
  results r
CROSS JOIN
  los_stats l
GROUP BY
  r.readmitted_patients, r.total_patients, r.los_gt_6_patients, r.readmitted_los_gt_6_patients;