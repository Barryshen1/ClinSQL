WITH first_admission AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
),
cabg_procedures AS (
  SELECT DISTINCT
    pi.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%cabg%'
     OR LOWER(dip.long_title) LIKE '%coronary artery bypass graft%'
)
SELECT 
  AVG(CAST(fa.hospital_expire_flag AS INT64)) AS in_hospital_mortality_rate
FROM first_admission fa
INNER JOIN cabg_procedures cp
  ON fa.hadm_id = cp.hadm_id
WHERE fa.rn = 1;