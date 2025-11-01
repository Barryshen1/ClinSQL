SELECT
  MIN(duration_days) AS min_atorva_duration_days
FROM (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(pr.dose_val_rx AS NUMERIC) BETWEEN 40 AND 80
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.starttime >= a.admittime
    AND pr.stoptime <= a.dischtime
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) >= 0
);