WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 43 AND 53
),
first_icu_stays AS (
  SELECT subject_id, stay_id, hadm_id, los,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE subject_id IN (SELECT subject_id FROM eligible_patients)
),
pneumonia_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 
         AND (icd_code LIKE '480%' OR icd_code LIKE '481%' OR icd_code LIKE '482%' 
              OR icd_code LIKE '483%' OR icd_code LIKE '484%' OR icd_code LIKE '485%' 
              OR icd_code LIKE '486%'))
     OR (icd_version = 10 
         AND (icd_code LIKE 'J12%' OR icd_code LIKE 'J13%' OR icd_code LIKE 'J14%' 
              OR icd_code LIKE 'J15%' OR icd_code LIKE 'J16%' OR icd_code LIKE 'J17%' 
              OR icd_code LIKE 'J18%'))
),
qualifying_stays AS (
  SELECT fis.los
  FROM first_icu_stays fis
  INNER JOIN pneumonia_admissions pa ON fis.hadm_id = pa.hadm_id
  WHERE fis.rn = 1
)
SELECT APPROX_QUANTILES(los, 5)[OFFSET(1)] AS p25_los_days
FROM qualifying_stays;