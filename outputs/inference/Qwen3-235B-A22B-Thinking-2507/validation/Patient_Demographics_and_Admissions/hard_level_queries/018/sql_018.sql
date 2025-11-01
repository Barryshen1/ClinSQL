WITH index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id AND a.subject_id = d_icd.subject_id
  WHERE 
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 58 AND 68
    AND d_icd.seq_num = 1
    AND (
      (d_icd.icd_version = 9 AND d_icd.icd_code = '8200')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'S720%')
    )
),
index_with_readmission AS (
  SELECT 
    ia.*,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` ra
      WHERE ra.subject_id = ia.subject_id
        AND ra.admittime > ia.dischtime
        AND ra.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM index_admissions ia
)
SELECT
  COUNT(*) AS total_index_admissions,
  SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END) AS readmitted_count,
  SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END), COUNT(*)) AS readmission_rate,
  APPROX_QUANTILES(IF(readmitted_30d, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(NOT readmitted_30d, los_days, NULL), 100)[OFFSET(50)] AS median_los_non_readmitted,
  SAFE_DIVIDE(COUNTIF(los_days > 8), COUNT(*)) * 100.0 AS percent_initial_stays_gt8
FROM index_with_readmission;