WITH sepsis_admissions AS (
  -- Step 1: Identify all hospital admissions with a diagnosis of sepsis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for sepsis, severe sepsis, and septic shock
    (icd_version = 9 AND icd_code IN ('99591', '99592', '78552'))
    -- ICD-10 codes for sepsis and severe sepsis
    OR (icd_version = 10 AND (icd_code LIKE 'A41%' OR icd_code LIKE 'R65.2%'))
),
first_platelet_counts AS (
  -- Step 2: Get the first platelet count for each admission within the first 24 hours
  SELECT
    le.hadm_id,
    le.valuenum,
    -- Rank measurements by time to find the first one
    ROW_NUMBER() OVER(PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON le.hadm_id = adm.hadm_id
  WHERE
    le.itemid = 51265 -- Platelet Count
    AND le.valuenum IS NOT NULL -- Ensure the value is numeric
    -- Filter for labs taken within the first 24 hours of admission
    AND le.charttime >= adm.admittime
    AND le.charttime <= DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
)
-- Step 3: Combine the data and calculate the final result
SELECT
  -- Calculate the sample standard deviation of the first platelet count
  STDDEV_SAMP(fpc.valuenum) AS sd_admission_platelet_count
FROM sepsis_admissions AS sa
-- Join with admissions and patients to filter for male patients
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON sa.hadm_id = adm.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
-- Join with the first platelet counts
INNER JOIN first_platelet_counts AS fpc
  ON sa.hadm_id = fpc.hadm_id
WHERE
  pat.gender = 'M' -- Filter for male patients
  AND fpc.rn = 1; -- Select only the first platelet measurement;