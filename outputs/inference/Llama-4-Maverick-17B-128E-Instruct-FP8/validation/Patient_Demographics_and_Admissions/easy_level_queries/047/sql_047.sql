WITH aki_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code IN ('5845', '5846', '5847', '5848', '5849'))
  OR (icd_version = 10 AND icd_code IN ('N17', 'N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9'))
),
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 82 AND 92
),
first_icu_stay AS (
  SELECT ie.hadm_id, ie.stay_id, ie.intime, ie.outtime,
         ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) AS icu_seq,
         DATETIME_DIFF(ie.outtime, ie.intime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),
filtered_patients AS (
  SELECT fp.subject_id, fis.hadm_id, fis.los_days
  FROM first_icu_stay fis
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON fis.hadm_id = adm.hadm_id
  JOIN female_patients fp ON adm.subject_id = fp.subject_id
  WHERE fis.icu_seq = 1 AND adm.hadm_id IN (SELECT hadm_id FROM aki_patients)
)
SELECT PERCENTILE_CONT(los_days, 0.25) OVER () AS percentile_25th
FROM filtered_patients
LIMIT 1;