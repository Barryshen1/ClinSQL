WITH ischemic_stroke_admissions AS (
  SELECT DISTINCT a.hadm_id, a.dischtime, p.subject_id, p.anchor_age, p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 94
    AND LOWER(did.long_title) LIKE '%ischemic stroke%'
),

glucose_on_discharge AS (
  SELECT l.valuenum AS glucose_value
  FROM ischemic_stroke_admissions isa
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents l ON isa.hadm_id = l.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%glucose%'
    AND LOWER(dl.label) LIKE '%serum%'
    AND DATE(l.charttime) = DATE(isa.dischtime)
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
)

SELECT 
  APPROX_QUANTILES(glucose_value, 4)[OFFSET(3)] - APPROX_QUANTILES(glucose_value, 4)[OFFSET(1)] AS iqr_glucose
FROM glucose_on_discharge;