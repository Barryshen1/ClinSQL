WITH dka_admissions AS (
  SELECT DISTINCT di.hadm_id, p.gender, p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON di.subject_id = p.subject_id
  WHERE LOWER(d.long_title) LIKE '%diabetic ketoacidosis%'
    AND p.gender = 'F'
    AND p.anchor_age = 58
),
glucose_measurements AS (
  SELECT le.hadm_id, le.valuenum
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%glucose%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
),
peak_glucose_per_admission AS (
  SELECT ga.hadm_id, MAX(gm.valuenum) AS peak_glucose
  FROM dka_admissions ga
  JOIN glucose_measurements gm ON ga.hadm_id = gm.hadm_id
  GROUP BY ga.hadm_id
)
SELECT PERCENTILE_CONT(peak_glucose, 0.5) AS median_peak_glucose
FROM peak_glucose_per_admission;