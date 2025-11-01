WITH patient_pop AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 90 AND 100
),
prescription_durations AS (
  SELECT 
    p.subject_id,
    pr.hadm_id,
    pr.drug,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN 
    patient_pop p ON pr.subject_id = p.subject_id
  WHERE 
    LOWER(pr.drug) LIKE '%spironolactone%' OR LOWER(pr.drug) LIKE '%eplerenone%'
),
single_prescriptions AS (
  SELECT 
    hadm_id, 
    drug, 
    duration_days
  FROM 
    prescription_durations
  WHERE 
    hadm_id IN (
      SELECT hadm_id
      FROM prescription_durations
      GROUP BY hadm_id, drug
      HAVING COUNT(*) = 1
    )
)
SELECT 
  drug,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM 
  single_prescriptions
GROUP BY 
  drug;