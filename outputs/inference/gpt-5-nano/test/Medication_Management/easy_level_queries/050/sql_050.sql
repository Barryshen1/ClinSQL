WITH eligible_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON p.subject_id = pat.subject_id
  WHERE
    p.drug IS NOT NULL
    AND (LOWER(p.drug) LIKE '%spironolactone%' OR LOWER(p.drug) LIKE '%eplerenone%')
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    -- prescription occurred during the admission
    AND p.starttime >= a.admittime
    AND p.stoptime <= a.dischtime
    -- age at admission filter: 64 <= age_at_adm <= 74
    AND pat.anchor_age IS NOT NULL
    AND pat.anchor_year IS NOT NULL
    AND (pat.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pat.anchor_year)) BETWEEN 64 AND 74
    -- male patients
    AND UPPER(pat.gender) = 'M'
)
SELECT
  AVG(TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 3600.0) AS average_duration_hours,
  (AVG(TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 3600.0)) / 24 AS average_duration_days
FROM eligible_prescriptions;