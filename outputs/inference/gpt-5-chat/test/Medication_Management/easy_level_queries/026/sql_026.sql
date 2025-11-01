WITH cohort AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    LOWER(pr.drug) AS drug_lower
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pr.subject_id = adm.subject_id
    AND pr.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pr.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND (
      LOWER(pr.drug) LIKE '%amlodipine%' OR
      LOWER(pr.drug) LIKE '%nifedipine%' OR
      LOWER(pr.drug) LIKE '%felodipine%' OR
      LOWER(pr.drug) LIKE '%nicardipine%' OR
      LOWER(pr.drug) LIKE '%isradipine%' OR
      LOWER(pr.drug) LIKE '%clevidipine%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
durations AS (
  SELECT
    subject_id,
    hadm_id,
    DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM cohort
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS p25_duration_days
FROM durations
LIMIT 1;