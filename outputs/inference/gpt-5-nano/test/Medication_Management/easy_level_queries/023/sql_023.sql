SELECT
  STDDEV_SAMP(duration_days) AS sd_days
FROM (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- duration in days as decimal
    CAST(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) AS FLOAT64) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
   AND a.hadm_id = pr.hadm_id
  WHERE
    -- Cohort: hospitalized women aged 78-88
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    -- ACE inhibitors (drug names containing 'pril')
    AND LOWER(pr.drug) LIKE '%pril%'
    -- Inpatient window constraints
    AND pr.starttime >= a.admittime
    AND pr.stoptime <= a.dischtime
    -- Ensure non-null durations
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
) AS sub;