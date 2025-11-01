SELECT
  AVG(TIMESTAMP_DIFF(TIMESTAMP(p.stoptime), TIMESTAMP(p.starttime), SECOND) / 86400.0) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
WHERE
  LOWER(p.drug) LIKE '%spironolactone%' OR LOWER(p.drug) LIKE '%eplerenone%'  -- Target medications
  AND pat.gender = 'M'  -- Male patients
  AND (EXTRACT(YEAR FROM a.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 64 AND 74  -- Age 64-74 at admission
  AND p.stoptime IS NOT NULL  -- Ensure valid duration
  AND p.stoptime > p.starttime;  -- Exclude negative durations;