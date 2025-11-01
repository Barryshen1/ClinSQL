WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE 
    p.anchor_age BETWEEN 50 AND 60
    AND p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND (
      -- ICD-10 codes
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'K92.0%' OR  -- Hematemesis
        diag.icd_code LIKE 'K92.1%' OR  -- Melaena
        diag.icd_code LIKE 'K92.2%' OR  -- Gastrointestinal hemorrhage, unspecified
        diag.icd_code LIKE 'K62.5%'     -- Hemorrhage of anus and rectum
      ))
      OR
      -- ICD-9 codes
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '578%'       -- Gastrointestinal hemorrhage
      ))
    )
    AND a.dischtime IS NOT NULL
    AND a.deathtime IS NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

readmissions AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.los_days,
    CASE WHEN readmit.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` readmit
    ON c.subject_id = readmit.subject_id
    AND readmit.admittime > c.dischtime
    AND readmit.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
    AND readmit.hadm_id != c.hadm_id
),

los_stats AS (
  SELECT
    readmitted_30d,
    PERCENTILE_DISC(los_days, 0.5) OVER(PARTITION BY readmitted_30d) AS median_los
  FROM readmissions
  GROUP BY readmitted_30d, los_days
)

SELECT 
  COUNT(*) AS total_patients,
  SUM(readmitted_30d) AS readmitted_count,
  ROUND(100.0 * SUM(readmitted_30d) / COUNT(*), 2) AS readmission_rate_percent,
  MAX(CASE WHEN readmitted_30d = 1 THEN median_los END) AS median_los_readmitted,
  MAX(CASE WHEN readmitted_30d = 0 THEN median_los END) AS median_los_not_readmitted,
  ROUND(100.0 * SUM(CASE WHEN readmitted_30d = 1 AND los_days > 6 THEN 1 ELSE 0 END) / NULLIF(SUM(readmitted_30d), 0), 2) AS pct_readmitted_los_gt_6,
  ROUND(100.0 * SUM(CASE WHEN readmitted_30d = 0 AND los_days > 6 THEN 1 ELSE 0 END) / NULLIF(COUNT(*) - SUM(readmitted_30d), 0), 2) AS pct_not_readmitted_los_gt_6
FROM readmissions
CROSS JOIN los_stats
GROUP BY readmitted_30d;