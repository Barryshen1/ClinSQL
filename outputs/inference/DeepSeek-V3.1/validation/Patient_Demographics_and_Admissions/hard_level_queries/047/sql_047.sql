WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 10 AND diag.icd_code IN ('I60', 'I61', 'I62')) 
      OR 
      (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432'))
    )
    -- Filter age at admission: 68 to 78
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    -- Exclude index admissions where the patient died
    AND adm.deathtime IS NULL
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT 
    c1.subject_id,
    c1.hadm_id AS index_hadm,
    c1.admittime AS index_admittime,
    c1.dischtime AS index_dischtime,
    c1.los AS index_los,
    MIN(c2.admittime) AS readmit_time
  FROM cohort c1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` c2
    ON c1.subject_id = c2.subject_id
    AND c2.admittime > c1.dischtime
    AND c2.admittime <= DATE_ADD(c1.dischtime, INTERVAL 30 DAY)
  GROUP BY c1.subject_id, c1.hadm_id, c1.admittime, c1.dischtime, c1.los
),

-- Add readmission flag
cohort_with_readmit_flag AS (
  SELECT 
    subject_id,
    index_hadm,
    index_los,
    CASE WHEN readmit_time IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM readmissions
)

-- Calculate metrics
SELECT
  COUNT(*) AS total_index_admissions,
  SUM(readmitted) AS readmitted_count,
  ROUND(SUM(readmitted) * 100.0 / COUNT(*), 2) AS readmission_rate_percent,
  -- Median LOS for readmitted: use approx_quantiles and take the 50th percentile
  APPROX_QUANTILES(CASE WHEN readmitted=1 THEN index_los END, 100)[OFFSET(50)] AS median_los_readmitted,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted=0 THEN index_los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  -- % with LOS >4 days for readmitted
  ROUND(SUM(CASE WHEN readmitted=1 AND index_los > 4 THEN 1 ELSE 0 END) * 100.0 / SUM(readmitted), 2) AS percent_readmitted_los_gt_4,
  -- % with LOS >4 days for non-readmitted
  ROUND(SUM(CASE WHEN readmitted=0 AND index_los > 4 THEN 1 ELSE 0 END) * 100.0 / (COUNT(*) - SUM(readmitted)), 2) AS percent_not_readmitted_los_gt_4
FROM cohort_with_readmit_flag;