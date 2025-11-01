WITH cellulitis_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    pat.gender,
    pat.anchor_age,
    adm.insurance,
    adm.admission_location,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    -- Rank admissions per patient to get the first eligible one
    ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1  -- principal diagnosis
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'L03%') 
      OR 
      (diag.icd_version = 9 AND (diag.icd_code LIKE '681%' OR diag.icd_code LIKE '682%'))
    )
    AND adm.hospital_expire_flag = 0  -- exclude deaths during index admission
),
index_admissions AS (
  SELECT * 
  FROM cellulitis_admissions 
  WHERE admission_rank = 1
),
readmission_flag AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id AS index_hadm,
    ia.admittime AS index_admittime,
    ia.dischtime AS index_dischtime,
    ia.los AS index_los,
    -- Check for any readmission within 30 days
    MAX(CASE 
        WHEN readm.hadm_id IS NOT NULL THEN 1 
        ELSE 0 
    END) AS readmitted_30d
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` readm
    ON ia.subject_id = readm.subject_id
    AND readm.admittime > ia.dischtime
    AND readm.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
  GROUP BY ia.subject_id, ia.hadm_id, ia.admittime, ia.dischtime, ia.los
)
SELECT 
  COUNT(*) AS total_index_admissions,
  AVG(readmitted_30d) * 100 AS readmission_rate_percent,
  -- Median LOS for readmitted: use approx_quantiles and get the 0.5 quantile (median)
  (SELECT approx_quantiles(index_los, 100)[OFFSET(50)] 
   FROM readmission_flag 
   WHERE readmitted_30d = 1) AS median_los_readmitted,
  -- Median LOS for non-readmitted
  (SELECT approx_quantiles(index_los, 100)[OFFSET(50)] 
   FROM readmission_flag 
   WHERE readmitted_30d = 0) AS median_los_non_readmitted,
  -- Percentage of index stays with LOS > 7 days
  AVG(CASE WHEN index_los > 7 THEN 1.0 ELSE 0.0 END) * 100 AS percent_los_gt_7_days
FROM readmission_flag;