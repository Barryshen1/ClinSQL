WITH index_adm AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id 
    AND d.seq_num = 1
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER'
    AND a.hospital_expire_flag = 0
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%') 
      OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
),
all_index_with_readmit AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.los_days,
    CASE WHEN COUNT(a2.hadm_id) > 0 THEN 1 ELSE 0 END AS readmitted_flag
  FROM index_adm i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON i.subject_id = a2.subject_id
    AND a2.hadm_id != i.hadm_id
    AND a2.admittime > i.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(i.dischtime, INTERVAL 30 DAY)
  GROUP BY i.subject_id, i.hadm_id, i.los_days
)
SELECT 
  COUNT(*) AS total_index_admissions,
  SUM(readmitted_flag) AS num_readmitted,
  ROUND(AVG(readmitted_flag) * 100, 2) AS readmission_rate_percent,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM all_index_with_readmit WHERE readmitted_flag = 1) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM all_index_with_readmit WHERE readmitted_flag = 0) AS median_los_not_readmitted_days,
  ROUND(COUNTIF(los_days > 4) * 100.0 / COUNT(*), 2) AS percent_stays_gt4days
FROM all_index_with_readmit;