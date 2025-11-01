WITH patient_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    DATEDIFF(p.stoptime, p.starttime) AS duration_days,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY p.starttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M'
    AND (LOWER(p.drug) LIKE '%spironolactone%' OR LOWER(p.drug) LIKE '%eplerenone%')
    AND a.admittime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND DATE_DIFF(
        a.admittime, 
        DATE_SUB(DATE(pt.anchor_year, 1, 1), INTERVAL pt.anchor_age YEAR), 
        YEAR
      ) BETWEEN 90 AND 100
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM patient_prescriptions
WHERE rn = 1;