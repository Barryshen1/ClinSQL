WITH index_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    CASE WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) > 6 THEN 1 ELSE 0 END AS los_gt_6
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON adm.hadm_id = diag.hadm_id 
    AND adm.subject_id = diag.subject_id
  WHERE 
    p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'M'
    AND adm.admission_location LIKE '%SNF%'  -- Changed to pattern match
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 10 AND diag.icd_code = 'N39.0') 
      OR 
      (diag.icd_version = 9 AND diag.icd_code = '599.0')
    )
    AND adm.hospital_expire_flag = 0  -- exclude died in hospital
),
readmission_flag AS (
  SELECT 
    ia.*,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm
      WHERE readm.subject_id = ia.subject_id
        AND readm.hadm_id != ia.hadm_id
        AND readm.admittime BETWEEN ia.dischtime AND DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM index_admissions ia
)
SELECT 
  COUNT(*) AS total_index_admissions,
  AVG(readmitted_30d) * 100 AS readmission_rate_percent,
  -- Median LOS for readmitted and non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los END, 2)[OFFSET(1)] AS median_los_non_readmitted,
  AVG(CASE WHEN readmitted_30d = 1 THEN los_gt_6 END) * 100 AS percent_los_gt6_readmitted,
  AVG(CASE WHEN readmitted_30d = 0 THEN los_gt_6 END) * 100 AS percent_los_gt6_non_readmitted
FROM readmission_flag;