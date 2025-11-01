SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS amiodarone_prescription_duration_25th_percentile_days
FROM (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON pr.subject_id = pa.subject_id
  WHERE
    pa.gender = 'F'
    AND pa.anchor_age BETWEEN 42 AND 52
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
);