WITH target_patients AS (
  SELECT
    p.subject_id,
    p.anchor_year,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
),
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    a.admission_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN target_patients p ON a.subject_id = p.subject_id
  WHERE
    a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0
    AND a.insurance LIKE '%Medicare%'
    AND a.admission_location LIKE '%EMERGENCY%'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 68 AND 78
),
admissions_with_next AS (
  SELECT
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admit
  FROM patient_admissions
),
index_admissions AS (
  SELECT
    a.*,
    d.icd_code,
    d.icd_version,
    CASE
      WHEN next_admit IS NOT NULL AND next_admit <= dischtime + INTERVAL 30 DAY THEN 1
      ELSE 0
    END AS readmitted
  FROM admissions_with_next a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code BETWEEN 'I60' AND 'I62') 
      OR 
      (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I62')
    )
),
metrics AS (
  SELECT
    COUNT(*) AS total_admissions,
    COUNT(CASE WHEN readmitted = 1 THEN 1 END) AS readmitted_count,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los_readmitted,
    (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM index_admissions WHERE readmitted = 0) AS median_los_non_readmitted,
    COUNT(CASE WHEN los > 4 THEN 1 END) AS los_gt4_count
  FROM index_admissions
)
SELECT
  (readmitted_count * 100.0 / total_admissions) AS readmission_rate,
  median_los_readmitted,
  median_los_non_readmitted,
  (los_gt4_count * 100.0 / total_admissions) AS percent_los_gt4
FROM metrics;