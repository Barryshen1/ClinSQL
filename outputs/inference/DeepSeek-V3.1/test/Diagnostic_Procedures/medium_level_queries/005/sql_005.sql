WITH stroke_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    diag.seq_num,
    CASE 
        WHEN diag.seq_num = 1 THEN 'Primary'
        ELSE 'Secondary'
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND d.icd_code LIKE 'I63%'
),
icu_stays AS (
  SELECT 
    hadm_id,
    stay_id,
    los,
    CASE 
        WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
    END AS stay_length_group
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE los BETWEEN 1 AND 8
),
procedures_count AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
combined AS (
  SELECT 
    sa.hadm_id,
    sa.diagnosis_type,
    isu.stay_length_group,
    COALESCE(pc.num_procedures, 0) AS num_procedures
  FROM stroke_admissions sa
  INNER JOIN icu_stays isu
    ON sa.hadm_id = isu.hadm_id
  LEFT JOIN procedures_count pc
    ON sa.hadm_id = pc.hadm_id
)
SELECT 
  stay_length_group,
  diagnosis_type,
  ROUND(AVG(num_procedures), 2) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures,
  COUNT(*) AS num_admissions
FROM combined
GROUP BY stay_length_group, diagnosis_type
ORDER BY stay_length_group, diagnosis_type;