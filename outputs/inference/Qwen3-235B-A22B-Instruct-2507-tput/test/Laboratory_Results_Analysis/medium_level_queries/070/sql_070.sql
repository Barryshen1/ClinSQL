WITH chest_pain_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
    ON diag.icd_code = d_diag.icd_code 
    AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%chest pain%'
),
troponin_i_first AS (
  SELECT 
    le.hadm_id,
    FIRST_VALUE(le.valuenum) OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS first_troponin_i
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab ON le.itemid = d_lab.itemid
  WHERE LOWER(d_lab.label) = 'troponin i'
    AND le.valuenum IS NOT NULL
),
eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
)
SELECT
  APPROX_QUANTILES(t.first_troponin_i, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(t.first_troponin_i, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(t.first_troponin_i, 1000)[OFFSET(750)] AS p75,
  MIN(t.first_troponin_i) AS min_value,
  MAX(t.first_troponin_i) AS max_value
FROM troponin_i_first t
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON t.hadm_id = adm.hadm_id
JOIN eligible_patients ep ON adm.subject_id = ep.subject_id
WHERE t.hadm_id IN (SELECT hadm_id FROM chest_pain_admissions)
  AND t.first_troponin_i IS NOT NULL;