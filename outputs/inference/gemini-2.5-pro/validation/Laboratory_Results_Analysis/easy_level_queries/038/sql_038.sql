WITH stroke_admissions AS (
  -- First, identify all hospital admissions (hadm_id) for ischemic stroke
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-10 codes for Ischemic Stroke start with 'I63'
    (icd_version = 10 AND icd_code LIKE 'I63%')
    OR
    -- ICD-9 codes for occlusion and stenosis of precerebral/cerebral arteries
    (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%'))
)
SELECT
  MIN(le.valuenum) AS min_hemoglobin_first_24h
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
-- Join with patients to filter by gender
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
-- Join with our CTE to only include ischemic stroke admissions
INNER JOIN stroke_admissions AS sa
  ON adm.hadm_id = sa.hadm_id
-- Join with labevents to find Hemoglobin measurements
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON adm.hadm_id = le.hadm_id
WHERE
  -- 1. Filter for male patients
  pat.gender = 'M'
  -- 2. Filter for Hemoglobin (itemid 51222)
  AND le.itemid = 51222
  -- 3. Ensure the value is a number
  AND le.valuenum IS NOT NULL
  -- 4. Filter for measurements taken within the first 24 hours of hospital admission
  AND le.charttime >= adm.admittime
  AND le.charttime <= TIMESTAMP_ADD(adm.admittime, INTERVAL 24 HOUR);