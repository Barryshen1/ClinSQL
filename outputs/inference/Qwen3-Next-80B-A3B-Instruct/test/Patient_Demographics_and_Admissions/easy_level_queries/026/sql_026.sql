WITH first_admission AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
cabg_procedures AS (
  SELECT DISTINCT
    pi.subject_id,
    pi.hadm_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    LOWER(dip.long_title) LIKE '%cabg%' 
    OR LOWER(dip.long_title) LIKE '%bypass%'
)
SELECT 
  APPROX_QUANTILES(CAST(hospital_expire_flag AS FLOAT64), 1)[OFFSET(0)] AS p25_inhospital_mortality
FROM 
  first_admission fa
INNER JOIN 
  cabg_procedures cp
  ON fa.subject_id = cp.subject_id 
  AND fa.hadm_id = cp.hadm_id
WHERE 
  fa.rn = 1;