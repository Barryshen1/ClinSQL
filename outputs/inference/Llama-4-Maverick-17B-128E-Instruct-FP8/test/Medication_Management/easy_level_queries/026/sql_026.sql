WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
),
prescription_durations AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN patient_filter p ON pr.subject_id = p.subject_id
  WHERE LOWER(pr.drug) LIKE '%dihydropyridine%' AND LOWER(pr.drug) LIKE '%ccb%'
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM prescription_durations;