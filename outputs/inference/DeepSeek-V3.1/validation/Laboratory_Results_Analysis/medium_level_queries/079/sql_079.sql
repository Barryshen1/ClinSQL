WITH qualifying_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.anchor_age BETWEEN 82 AND 92
    AND pat.gender = 'F'
    AND (diag.icd_code = 'R07.9' OR diag.icd_code LIKE 'I21%')
    AND diag.icd_version = 10
),
first_troponin AS (
  SELECT 
    qa.subject_id,
    qa.hadm_id,
    qa.anchor_age,
    le.charttime,
    le.valuenum AS troponin_value
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON qa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.label = 'Troponin T'
    AND le.valuenum > 0.01
  QUALIFY ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY le.charttime) = 1
)
SELECT 
  MIN(troponin_value) AS min_value,
  MAX(troponin_value) AS max_value,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] AS p75
FROM first_troponin;