WITH
-- Identify admissions with an AMI diagnosis (ICD-9: 410*, ICD-10: I21*, I22*)
ami_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code LIKE '410%')
    OR
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),

-- Base cohort: male inpatients aged 67-77 with an AMI admission
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hadm_id IN (SELECT hadm_id FROM ami_hadm)
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Compute medication complexity score: count distinct prescribed drugs started in first 24 hours
med_scores AS (
  SELECT
    c.hadm_id,
    COALESCE(COUNT(DISTINCT TRIM(LOWER(pr.drug))), 0) AS med_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
    AND pr.starttime IS NOT NULL
    AND pr.starttime >= c.admittime
    AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND TRIM(pr.drug) <> ''
  GROUP BY c.hadm_id
),

-- Combine cohort with scores, compute LOS and 30-day readmission flag
admissions_with_metrics AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(ms.med_score, 0) AS med_score,
    -- LOS in fractional days
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / 86400.0 AS los_days,
    c.hospital_expire_flag,
    -- 30-day readmission indicator: existence of subsequent admission within 30 days after discharge
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit30
  FROM cohort c
  LEFT JOIN med_scores ms USING (hadm_id)
),

-- Assign tertiles across admissions by med_score (ties deterministically broken by hadm_id)
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_score, hadm_id) AS tertile
  FROM admissions_with_metrics
)

-- Final aggregation per tertile
SELECT
  tertile,
  COUNT(1) AS admission_count,
  MIN(med_score) AS score_min,
  MAX(med_score) AS score_max,
  ROUND(AVG(med_score), 2) AS score_mean,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(CAST(readmit30 AS FLOAT64)) * 100, 2) AS readmit_30day_pct
FROM tertiles
GROUP BY tertile
ORDER BY tertile;