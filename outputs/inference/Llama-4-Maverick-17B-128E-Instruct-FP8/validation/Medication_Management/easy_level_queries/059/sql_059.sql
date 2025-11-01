WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 38 AND 48
),
arb_prescriptions AS (
  SELECT p.subject_id, pr.starttime, pr.stoptime,
         DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM patient_filter p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%valsartan%' 
    OR LOWER(pr.drug) LIKE '%candesartan%' OR LOWER(pr.drug) LIKE '%irbesartan%' 
    OR LOWER(pr.drug) LIKE '%olmesartan%' OR LOWER(pr.drug) LIKE '%telmisartan%' 
    OR LOWER(pr.drug) LIKE '%eprosartan%' OR LOWER(pr.drug) LIKE '%azilsartan%' 
    OR LOWER(pr.drug) LIKE '%fimasartan%'  -- Including various ARBs
)
SELECT APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS percentile_75th
FROM arb_prescriptions;