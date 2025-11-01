WITH 
cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 76 AND 86
  AND a.insurance = 'Medicare'
),

ischemic_stroke_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
         ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort ON a.subject_id = cohort.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE a.admission_location = 'EMERGENCY DEPARTMENT'
  AND di.seq_num = 1  
  AND dicd.icd_version = 10  
  AND dicd.icd_code LIKE 'I63%'  
),

readmission_status AS (
  SELECT hadm_id, subject_id, admittime, dischtime, los, admission_seq,
         LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admit,
         CASE 
           WHEN LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) <= (dischtime + INTERVAL 30 DAY) THEN 1
           ELSE 0
         END AS readmitted_within_30_days
  FROM ischemic_stroke_admissions
  WHERE admission_seq = 1  
),

final_metrics AS (
  SELECT 
    SUM(readmitted_within_30_days) / COUNT(*) AS thirty_day_readmission_rate,
    (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM UNNEST([los]) AS los WHERE readmitted_within_30_days = 1) AS median_los_readmitted,
    (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM UNNEST([los]) AS los WHERE readmitted_within_30_days = 0) AS median_los_not_readmitted,
    AVG(CASE WHEN los > 5 THEN 1 ELSE 0 END) * 100 AS percent_stays_gt_5_days
  FROM readmission_status
)

SELECT 
  thirty_day_readmission_rate,
  median_los_readmitted,
  median_los_not_readmitted,
  percent_stays_gt_5_days
FROM final_metrics;