WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    diag.seq_num,
    CASE 
        WHEN diag.seq_num = 1 THEN 'primary'
        ELSE 'secondary'
    END AS diagnosis_type,
    icu.stay_id,
    icu.los AS icu_los_days,
    CASE 
        WHEN icu.los BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN icu.los BETWEEN 5 AND 8 THEN '5-8 days'
    END AS icu_stay_category
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (d.long_title LIKE '%acute coronary syndrome%' 
         OR d.long_title LIKE '%myocardial infarction%' 
         OR d.long_title LIKE '%unstable angina%')
    AND icu.los BETWEEN 1 AND 8
),

radiology_procedures AS (
  SELECT 
    proc.hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code AND proc.icd_version = d.icd_version
  WHERE 
    d.long_title LIKE '%computed tomography%' 
    OR d.long_title LIKE '%radiograph%'
  GROUP BY proc.hadm_id
)

SELECT 
  a.icu_stay_category,
  a.diagnosis_type,
  COUNT(DISTINCT a.hadm_id) AS num_admissions,
  AVG(COALESCE(r.procedure_count, 0)) AS mean_procedures,
  MIN(COALESCE(r.procedure_count, 0)) AS min_procedures,
  MAX(COALESCE(r.procedure_count, 0)) AS max_procedures
FROM acs_admissions a
LEFT JOIN radiology_procedures r
  ON a.hadm_id = r.hadm_id
GROUP BY a.icu_stay_category, a.diagnosis_type
ORDER BY a.icu_stay_category, a.diagnosis_type;