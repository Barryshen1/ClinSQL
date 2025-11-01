WITH acs_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    di.seq_num,
    i.los
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND LOWER(dic.long_title) LIKE '%acute coronary syndrome%'
),

ultrasound_counts AS (
  SELECT
    ap.hadm_id,
    ap.seq_num,
    ap.los,
    COUNT(*) AS count_ultrasounds
  FROM acs_patients ap
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON ap.hadm_id = pe.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ultrasound%'
  GROUP BY ap.hadm_id, ap.seq_num, ap.los
),

stratified AS (
  SELECT
    CASE
      WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    CASE
      WHEN seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type,
    count_ultrasounds
  FROM ultrasound_counts
  WHERE los BETWEEN 1 AND 7
)

SELECT
  los_group,
  diagnosis_type,
  AVG(count_ultrasounds) AS mean_ultrasounds,
  MIN(count_ultrasounds) AS min_ultrasounds,
  MAX(count_ultrasounds) AS max_ultrasounds
FROM stratified
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;