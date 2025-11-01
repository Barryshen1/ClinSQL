SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr
FROM (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND p.hadm_id = a.hadm_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 75 AND 85
    AND p.drug LIKE '%atorvastatin%'
    AND p.dose_val_rx BETWEEN 40 AND 80
    AND p.dose_unit_rx = 'mg'
    AND p.stoptime IS NOT NULL
);