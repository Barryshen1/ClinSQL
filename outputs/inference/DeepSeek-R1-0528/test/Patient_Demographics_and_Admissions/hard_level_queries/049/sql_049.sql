WITH index_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    p.anchor_age, 
    p.anchor_year,
    p.gender,
    adm.insurance,
    adm.admission_location
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON adm.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON adm.hadm_id = diag.hadm_id 
      AND adm.subject_id = diag.subject_id
  WHERE 
    diag.seq_num = 1
    AND p.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'SNF'
    AND adm.hospital_expire_flag = 0
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%') 
      OR 
      (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 61 AND 71
),

index_adm_with_readmission_flag AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2
      WHERE 
        adm2.subject_id = ia.subject_id
        AND adm2.hadm_id != ia.hadm_id
        AND adm2.admittime > ia.dischtime
        AND adm2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmission_flag
  FROM index_admissions ia
),

overall_stats AS (
  SELECT 
    AVG(readmission_flag) * 100 AS readmission_rate,
    AVG(CASE WHEN los_days > 6 THEN 1.0 ELSE 0.0 END) * 100 AS pct_index_stays_gt_6_days
  FROM index_adm_with_readmission_flag
),

median_stats AS (
  SELECT 
    readmission_flag,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM index_adm_with_readmission_flag
  GROUP BY readmission_flag
),

pivoted_medians AS (
  SELECT 
    MAX(CASE WHEN readmission_flag = 1 THEN median_los END) AS median_los_readmitted,
    MAX(CASE WHEN readmission_flag = 0 THEN median_los END) AS median_los_non_readmitted
  FROM median_stats
)

SELECT 
  readmission_rate,
  median_los_readmitted,
  median_los_non_readmitted,
  pct_index_stays_gt_6_days
FROM overall_stats, pivoted_medians;