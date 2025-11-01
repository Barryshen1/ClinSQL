WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
)

SELECT
  AVG(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS avg_duration_days
FROM patient_admissions pa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON pa.subject_id = pr.subject_id
  AND pa.hadm_id = pr.hadm_id
WHERE
  pa.admission_age BETWEEN 43 AND 53
  AND LOWER(pr.drug) LIKE '%warfarin%'  -- Case-insensitive match
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime >= pr.starttime;  -- Exclude negative durations;