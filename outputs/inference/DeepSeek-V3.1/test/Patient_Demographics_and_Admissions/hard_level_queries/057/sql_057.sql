WITH index_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.insurance,
    adm.admission_location,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    p.anchor_age,
    p.gender,
    ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS admission_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND diag.icd_code = 'N39.0'
    AND diag.icd_version = 10
),
readmission_flag AS (
  SELECT 
    ia.*,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm
      WHERE readm.subject_id = ia.subject_id
        AND readm.admittime > ia.dischtime
        AND readm.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
        AND readm.hadm_id != ia.hadm_id
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM index_admissions ia
  WHERE ia.admission_seq = 1
)
SELECT 
  100.0 * SUM(readmitted_30d) / COUNT(*) AS readmission_rate_percent,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_non_readmitted,
  100.0 * SUM(CASE WHEN readmitted_30d = 1 AND los_days > 9 THEN 1 ELSE 0 END) / SUM(readmitted_30d) AS pct_los_gt_9_readmitted,
  100.0 * SUM(CASE WHEN readmitted_30d = 0 AND los_days > 9 THEN 1 ELSE 0 END) / SUM(CASE WHEN readmitted_30d = 0 THEN 1 ELSE 0 END) AS pct_los_gt_9_non_readmitted
FROM readmission_flag;