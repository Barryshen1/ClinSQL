WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id, a.dischtime, p.gender, p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age >= 93
    AND LOWER(d_icd.long_title) LIKE '%sepsis%'
),
platelet_measurements AS (
  SELECT ce.valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN sepsis_admissions sa ON ce.hadm_id = sa.hadm_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
  WHERE LOWER(di.label) IN ('platelets', 'plt', 'platelet count', 'platelet count (automated)', 'platelet count (manual)')
    AND ce.valuenum IS NOT NULL
    AND DATE(ce.charttime) = DATE(sa.dischtime)
)
SELECT APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75_platelet_count
FROM platelet_measurements;