WITH pneumonia_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%pneumonia%'
),
male_95_pneumonia AS (
  SELECT p.subject_id, p.anchor_age, pa.hadm_id
  FROM pneumonia_admissions pa
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON pa.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age = 95
),
creatinine_values AS (
  SELECT le.hadm_id, le.valuenum
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%creat%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.valuenum < 50
),
peak_creatinine_per_admission AS (
  SELECT ma.hadm_id, MAX(cv.valuenum) AS peak_creatinine
  FROM male_95_pneumonia ma
  JOIN creatinine_values cv
    ON ma.hadm_id = cv.hadm_id
  GROUP BY ma.hadm_id
)
SELECT STDDEV(peak_creatinine) AS std_dev_peak_creatinine
FROM peak_creatinine_per_admission;