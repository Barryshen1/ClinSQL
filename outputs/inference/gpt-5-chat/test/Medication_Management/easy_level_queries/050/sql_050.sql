WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
)
SELECT
  AVG(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0) AS avg_prescription_duration_days
FROM cohort c
JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON c.subject_id = pr.subject_id
  AND c.hadm_id = pr.hadm_id
WHERE c.age_at_admit BETWEEN 64 AND 74
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND (
    LOWER(pr.drug) LIKE '%spironolactone%'
    OR LOWER(pr.drug) LIKE '%eplerenone%'
  );