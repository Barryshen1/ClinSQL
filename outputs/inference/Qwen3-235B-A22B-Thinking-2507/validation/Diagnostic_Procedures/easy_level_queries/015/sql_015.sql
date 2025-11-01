WITH age_adm AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
filtered_adm AS (
  SELECT 
    subject_id,
    hadm_id
  FROM age_adm
  WHERE gender = 'M'
    AND age BETWEEN 45 AND 55
),
cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE (icd_version = 9 AND icd_code LIKE '361%')
     OR (icd_version = 10 AND icd_code LIKE '021%')
),
adm_with_cabg AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id
  FROM filtered_adm fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON fa.hadm_id = pi.hadm_id
  INNER JOIN cabg_codes cc
    ON pi.icd_code = cc.icd_code 
    AND pi.icd_version = cc.icd_version
  GROUP BY fa.subject_id, fa.hadm_id
),
patient_cabg_count AS (
  SELECT 
    fa.subject_id,
    COUNT(awc.hadm_id) AS cabg_count
  FROM filtered_adm fa
  LEFT JOIN adm_with_cabg awc
    ON fa.subject_id = awc.subject_id 
    AND fa.hadm_id = awc.hadm_id
  GROUP BY fa.subject_id
)
SELECT 
  PERCENTILE_CONT(cabg_count, 0.25) OVER () AS percentile_25
FROM patient_cabg_count
LIMIT 1;