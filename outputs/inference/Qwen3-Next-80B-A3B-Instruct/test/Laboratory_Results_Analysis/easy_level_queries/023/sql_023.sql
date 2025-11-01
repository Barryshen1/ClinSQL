WITH sepsis_male_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND LOWER(d_icd.long_title) LIKE '%sepsis%'
),
lactate_on_discharge_day AS (
  SELECT
    l.valuenum
  FROM sepsis_male_admissions sma
  JOIN physionet-data.mimiciv_3_1_hosp.labevents l
    ON sma.hadm_id = l.hadm_id AND sma.subject_id = l.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) = 'lactate'
    AND DATE(l.charttime) = DATE(sma.dischtime)
    AND l.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(valuenum, 0.25) OVER () AS q1,
  PERCENTILE_CONT(valuenum, 0.75) OVER () AS q3,
  PERCENTILE_CONT(valuenum, 0.75) OVER () - PERCENTILE_CONT(valuenum, 0.25) OVER () AS iqr
FROM lactate_on_discharge_day
LIMIT 1;