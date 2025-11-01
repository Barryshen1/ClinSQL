WITH pneumonia_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 51 AND 61
  AND dicd.long_title LIKE '%Pneumonia%'
),
first_icu_admissions AS (
  SELECT subject_id, hadm_id, stay_id, intime, outtime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS icu_admission_num
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS percentile_25th
FROM (
  SELECT subject_id, DATETIME_DIFF(outtime, intime, DAY) AS icu_los
  FROM first_icu_admissions
  WHERE icu_admission_num = 1 AND subject_id IN (SELECT subject_id FROM pneumonia_patients)
);