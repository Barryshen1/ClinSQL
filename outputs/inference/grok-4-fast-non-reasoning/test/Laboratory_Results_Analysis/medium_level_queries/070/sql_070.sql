WITH qualifying_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
chest_pain_adms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN qualifying_patients qp ON di.subject_id = qp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
    ON di.icd_code = d_icd.icd_code 
    AND di.icd_version = d_icd.icd_version
  WHERE di.icd_version = '10'
    AND di.icd_code LIKE 'R071%'
),
troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponini%' 
    AND category = 'Chemistry'
),
initial_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    FIRST_VALUE(le.valuenum) OVER (
      PARTITION BY le.subject_id, le.hadm_id 
      ORDER BY le.charttime
    ) AS initial_troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_itemids ti ON le.itemid = ti.itemid
  JOIN chest_pain_adms cpa ON le.subject_id = cpa.subject_id AND le.hadm_id = cpa.hadm_id
  WHERE le.valuenum IS NOT NULL 
    AND le.valuenum > 0.04  -- Elevated threshold (ng/mL)
    AND le.valueuom = 'ng/mL'
),
unique_initial_values AS (
  SELECT DISTINCT 
    initial_troponin_value
  FROM initial_troponin
  WHERE initial_troponin_value IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(initial_troponin_value, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(initial_troponin_value, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(initial_troponin_value, 4)[OFFSET(3)] AS p75,
  MIN(initial_troponin_value) AS min_value,
  MAX(initial_troponin_value) AS max_value
FROM unique_initial_values;