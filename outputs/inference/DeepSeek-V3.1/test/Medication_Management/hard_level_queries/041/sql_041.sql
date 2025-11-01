WITH hf_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND diag.icd_code LIKE 'I50%'
    AND diag.icd_version = 10
    AND adm.dischtime IS NOT NULL  -- Exclude ongoing admissions
),

med_score AS (
  SELECT 
    pres.hadm_id,  -- Qualified to resolve ambiguity
    COUNT(DISTINCT drug) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  INNER JOIN hf_admissions adm
    ON pres.hadm_id = adm.hadm_id
  WHERE 
    DATETIME_DIFF(pres.starttime, adm.admittime, DAY) BETWEEN 0 AND 7
  GROUP BY pres.hadm_id
),

quintiles AS (
  SELECT 
    ms.hadm_id,
    ms.complexity_score,
    NTILE(5) OVER (ORDER BY ms.complexity_score) AS quintile
  FROM med_score ms
),

readmission_flag AS (
  SELECT 
    adm1.hadm_id,
    MAX(CASE WHEN adm2.admittime <= DATETIME_ADD(adm1.dischtime, INTERVAL 30 DAY) 
             AND adm2.admittime > adm1.dischtime THEN 1 ELSE 0 END) AS readmit_30d
  FROM hf_admissions adm1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON adm1.subject_id = adm2.subject_id
    AND adm2.admittime > adm1.dischtime  -- Removed redundant condition, added to CASE statement
  GROUP BY adm1.hadm_id
)

SELECT 
  q.quintile,
  COUNT(DISTINCT ha.hadm_id) AS patient_count,
  MIN(q.complexity_score) AS min_score,
  MAX(q.complexity_score) AS max_score,
  ROUND(AVG(ha.los_days), 2) AS mean_los_days,
  SUM(ha.hospital_expire_flag) AS in_hospital_mortality,
  SUM(rf.readmit_30d) AS readmission_30d
FROM hf_admissions ha
INNER JOIN quintiles q ON ha.hadm_id = q.hadm_id
LEFT JOIN readmission_flag rf ON ha.hadm_id = rf.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;