WITH male_67_pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON diag.icd_code = did.icd_code AND diag.icd_version = did.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 67
    AND (
      -- ICD-10 pneumonia codes
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J1%')
      -- ICD-9 pneumonia codes
      OR (diag.icd_version = 9 AND diag.icd_code IN ('480','481','482','483','484','485','486'))
    )
),
serum_glucose_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%glucose%'
    AND LOWER(fluid) LIKE '%serum%'
),
glucose_in_24h AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    le.charttime,
    le.valuenum
  FROM male_67_pneumonia_admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
  JOIN serum_glucose_items sgi
    ON le.itemid = sgi.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 24 HOUR)
),
mean_glucose_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    AVG(valuenum) AS mean_serum_glucose
  FROM glucose_in_24h
  GROUP BY subject_id, hadm_id
)
SELECT
  PERCENTILE_CONT(mean_serum_glucose, 0.75) OVER() AS percentile_75_mean_serum_glucose
FROM mean_glucose_per_admission
;