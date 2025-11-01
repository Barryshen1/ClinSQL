WITH pneumonia_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 'ICD-10' AND REGEXP_CONTAINS(icd_code, r'^J(09|1[0-8])'))
     OR (icd_version = 'ICD-9' AND REGEXP_CONTAINS(icd_code, r'^480|481|482|483|484|485|486$'))
),
first_icu_stays AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.seq_num = 1
    AND d.icd_code IN (SELECT icd_code FROM pneumonia_codes)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) = 1
)
SELECT 
  PERCENTILE_CONT(0.25) OVER() AS p25_los_days
FROM first_icu_stays;