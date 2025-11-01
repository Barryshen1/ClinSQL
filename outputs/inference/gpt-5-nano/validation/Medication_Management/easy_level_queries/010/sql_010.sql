WITH admissions_with_age AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
),
nitrate_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN admissions_with_age AS aw
    ON pr.subject_id = aw.subject_id
   AND pr.hadm_id = aw.hadm_id
  WHERE LOWER(pr.drug) LIKE '%nitro%' OR LOWER(pr.drug) LIKE '%nitrate%'
    AND pr.starttime >= aw.admittime
    AND pr.stoptime <= aw.dischtime
)
SELECT
  STDDEV_SAMP(duration_days) AS nitrate_duration_sd_days
FROM (
  SELECT
    np.hadm_id,
    np.subject_id,
    CAST(TIMESTAMP_DIFF(np.stoptime, np.starttime, SECOND) AS FLOAT64) / 86400.0 AS duration_days
  FROM nitrate_prescriptions AS np
) AS durations;