WITH 
eligible_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, 
         p.gender, p.anchor_age, p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.insurance = 'Medicare'
    AND p.gender = 'F'
    AND (p.anchor_year + p.anchor_age) BETWEEN (EXTRACT(YEAR FROM a.admittime) - 71) AND (EXTRACT(YEAR FROM a.admittime) - 61)
    AND a.admission_location = 'SNF'
),

akf_admissions AS (
  SELECT ep.subject_id, ep.hadm_id, ep.admittime, ep.dischtime
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ep.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE di.seq_num = 1 AND dicd.long_title LIKE '%Acute kidney injury%'
),

readmissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime, 
         DATETIME_DIFF(dischtime, admittime, DAY) AS los,
         LAG(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_admittime,
         DATETIME_DIFF(admittime, LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime), DAY) AS readmit_time
  FROM akf_admissions
),

index_admissions AS (
  SELECT hadm_id, los, 
         CASE WHEN readmit_time <= 30 THEN TRUE ELSE FALSE END AS readmitted
  FROM readmissions
  WHERE prev_admittime IS NOT NULL OR readmit_time IS NULL  
),

metrics AS (
  SELECT 
    COUNT(CASE WHEN readmitted THEN hadm_id END) AS readmitted_count,
    COUNT(hadm_id) AS total_count,
    COUNT(CASE WHEN los > 6 THEN hadm_id END) AS los_gt_6_count,
    APPROX_QUANTILES(CASE WHEN readmitted THEN los ELSE NULL END, 1000)[OFFSET(500)] AS median_los_readmitted,
    APPROX_QUANTILES(CASE WHEN NOT readmitted THEN los ELSE NULL END, 1000)[OFFSET(500)] AS median_los_not_readmitted
  FROM index_admissions
)

SELECT 
  SAFE_DIVIDE(readmitted_count, total_count) * 100 AS readmission_rate,
  median_los_readmitted,
  median_los_not_readmitted,
  SAFE_DIVIDE(los_gt_6_count, total_count) * 100 AS percent_los_gt_6
FROM metrics
WHERE total_count > 0;