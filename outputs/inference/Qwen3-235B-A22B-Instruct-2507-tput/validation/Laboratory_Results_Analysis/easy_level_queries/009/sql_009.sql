WITH acs_diagnoses AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(d.long_title) LIKE '%myocardial infarction%'
     OR LOWER(d.long_title) LIKE '%unstable angina%'
),
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),
nadir_troponin_per_admission AS (
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS nadir_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti ON le.itemid = ti.itemid
  JOIN acs_diagnoses ad ON le.hadm_id = ad.hadm_id
  JOIN female_patients fp ON le.subject_id = fp.subject_id
  WHERE le.valuenum IS NOT NULL
    AND le.valuenum >= 0
  GROUP BY le.hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_troponin, 100)[OFFSET(25)] AS troponin_25th_percentile
FROM nadir_troponin_per_admission;