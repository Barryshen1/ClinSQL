SELECT
  -- IQR = Q3 - Q1
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS digoxin_duration_iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quartiles
  FROM (
    SELECT
      p.subject_id,
      pr.hadm_id,
      TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON a.subject_id = pr.subject_id
      AND a.hadm_id = pr.hadm_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 86 AND 96
      AND LOWER(pr.drug) LIKE '%digoxin%'
      AND pr.starttime IS NOT NULL
      AND pr.stoptime IS NOT NULL
  )
);