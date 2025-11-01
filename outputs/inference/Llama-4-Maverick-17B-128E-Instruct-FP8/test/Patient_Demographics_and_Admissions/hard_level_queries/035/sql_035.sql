WITH 
eligible_patients AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.admission_location = 'SNF'
  AND p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND p.anchor_age BETWEEN 68 AND 78
),
uti_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM eligible_patients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE d.seq_num = 1  
  AND LOWER(dicd.long_title) LIKE '%urinary tract infection%'
),
index_admission AS (
  SELECT subject_id, hadm_id, admittime, dischtime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank,
         LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM eligible_patients
  WHERE hadm_id IN (SELECT hadm_id FROM uti_patients)
),
readmission_status AS (
  SELECT subject_id, hadm_id, admittime, dischtime,
         CASE WHEN next_admittime IS NOT NULL AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1 ELSE 0 END AS readmitted
  FROM index_admission
  WHERE admission_rank = 1  
),
los_data AS (
  SELECT subject_id, hadm_id, admittime, dischtime, readmitted,
         DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM readmission_status
)
SELECT 
  AVG(readmitted) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN los END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  AVG(CASE WHEN los > 6 THEN 1 ELSE 0 END) AS percent_stays_gt_6_days
FROM los_data;