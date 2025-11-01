WITH base_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%'))
    )
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
),
readmission_flag AS (
  SELECT 
    bc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE 
          a2.subject_id = bc.subject_id
          AND a2.admittime > bc.dischtime
          AND a2.admittime <= bc.dischtime + INTERVAL 30 DAY
      ) THEN 1
      ELSE 0
    END AS is_readmitted
  FROM base_cohort bc
)
SELECT
  SAFE_DIVIDE(SUM(is_readmitted) * 1.0, COUNT(*)) AS readmission_rate,
  APPROX_QUANTILES(IF(is_readmitted = 1, los_days, NULL), 100)[SAFE_OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(is_readmitted = 0, los_days, NULL), 100)[SAFE_OFFSET(50)] AS median_los_non_readmitted,
  SAFE_DIVIDE(COUNTIF(los_days > 4) * 100.0, COUNT(*)) AS percent_los_gt4
FROM readmission_flag;