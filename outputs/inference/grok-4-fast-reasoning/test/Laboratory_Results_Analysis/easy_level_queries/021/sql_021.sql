WITH pneumonia_male_hadms AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 9 
       AND (d.icd_code LIKE '480%' OR d.icd_code LIKE '481%' OR d.icd_code LIKE '482%' 
            OR d.icd_code LIKE '483%' OR d.icd_code LIKE '484%' OR d.icd_code LIKE '485%' 
            OR d.icd_code LIKE '486%'))
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J1[2-8]%')
    )
),
glucose_at_discharge AS (
  SELECT 
    le.hadm_id,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN pneumonia_male_hadms pmh
    ON le.hadm_id = pmh.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE le.itemid = 225655
    AND le.valuenum IS NOT NULL
    AND le.charttime <= a.dischtime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime DESC) = 1
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.75) AS p75_serum_glucose_mg_dl
FROM glucose_at_discharge;