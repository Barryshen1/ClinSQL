WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 76 AND 86
),
nitrate_prescriptions AS (
  SELECT p.subject_id, p.starttime, p.stoptime,
         DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN patient_filter pf ON p.subject_id = pf.subject_id
  WHERE LOWER(p.drug) LIKE '%nitroglycerin%' OR LOWER(p.drug) LIKE '%isosorbide%'
)
SELECT APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration
FROM nitrate_prescriptions;