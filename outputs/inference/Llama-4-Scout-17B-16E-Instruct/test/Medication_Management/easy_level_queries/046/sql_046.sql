WITH 
-- Filter patients aged 90-100 and male
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age BETWEEN 90 AND 100 AND gender = 'M'
),

-- Filter spironolactone/eplerenone prescriptions
spironolactone_prescriptions AS (
  SELECT p.subject_id, pr.hadm_id, pr.starttime, pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN patients_filtered p ON pr.subject_id = p.subject_id
  WHERE LOWER(pr.drug) IN ('spironolactone', 'eplerenone')
)

-- Calculate duration for each prescription and calculate median
SELECT 
  APPROX_QUANTILES(DATE_DIFF(stoptime, starttime, DAY), 1000)[500] AS median_duration
FROM 
  spironolactone_prescriptions;