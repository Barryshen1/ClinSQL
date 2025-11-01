WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'M'
    AND (
      ddiag.long_title LIKE '%pneumonia%'
      OR diag.icd_code LIKE '480%' OR diag.icd_code LIKE '481%' 
      OR diag.icd_code LIKE '482%' OR diag.icd_code LIKE '483%' 
      OR diag.icd_code LIKE '484%' OR diag.icd_code LIKE '485%' 
      OR diag.icd_code LIKE '486%' OR diag.icd_code = '487.0'
      OR diag.icd_code LIKE 'J12%' OR diag.icd_code LIKE 'J13%'
      OR diag.icd_code LIKE 'J14%' OR diag.icd_code LIKE 'J15%'
      OR diag.icd_code LIKE 'J16%' OR diag.icd_code LIKE 'J17%'
      OR diag.icd_code LIKE 'J18%'
    )
),
last_glucose AS (
  SELECT 
    pa.hadm_id,
    FIRST_VALUE(le.valuenum) OVER (
      PARTITION BY pa.hadm_id
      ORDER BY ABS(TIMESTAMP_DIFF(adm.dischtime, le.charttime, SECOND))
    ) AS glucose_value
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pa.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id AND pa.subject_id = le.subject_id
  WHERE le.itemid = 50809  -- Glucose (serum)
    AND le.valuenum IS NOT NULL
    AND le.charttime <= adm.dischtime
)
SELECT 
  APPROX_QUANTILES(glucose_value, 100)[OFFSET(75)] AS percentile_75
FROM last_glucose;