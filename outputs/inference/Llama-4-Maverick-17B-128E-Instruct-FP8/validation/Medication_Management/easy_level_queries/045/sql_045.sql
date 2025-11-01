WITH patient_info AS (
  SELECT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` USING (subject_id)
  WHERE gender = 'M' AND anchor_age BETWEEN 57 AND 67
),
dapt_medications AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%clopidogrel%' OR LOWER(drug) LIKE '%prasugrel%' OR LOWER(drug) LIKE '%ticagrelor%'
),
dapt_prescriptions AS (
  SELECT pi.hadm_id, 
         p.starttime, 
         p.stoptime, 
         DATETIME_DIFF(p.stoptime, p.starttime, MINUTE) AS duration_minutes,
         p.drug
  FROM patient_info pi
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON pi.hadm_id = p.hadm_id
  JOIN dapt_medications dm ON p.drug = dm.drug
  WHERE p.starttime IS NOT NULL AND p.stoptime IS NOT NULL
),
hadm_durations AS (
  SELECT hadm_id, 
         COUNT(DISTINCT drug) AS num_prescriptions
  FROM dapt_prescriptions
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT drug) > 1  -- Ensuring DAPT (more than one anti-platelet)
),
single_hadm_durations AS (
  SELECT dp.duration_minutes
  FROM hadm_durations hd
  JOIN dapt_prescriptions dp ON hd.hadm_id = dp.hadm_id
  WHERE hd.num_prescriptions = 1  -- Single inpatient DAPT prescription
)

SELECT 
  quantiles[OFFSET(25)] AS Q1,
  quantiles[OFFSET(75)] AS Q3,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS IQR
FROM (
  SELECT APPROX_QUANTILES(duration_minutes, 100) AS quantiles
  FROM single_hadm_durations
);