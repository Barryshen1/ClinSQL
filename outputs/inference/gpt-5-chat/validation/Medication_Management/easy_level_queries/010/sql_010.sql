SELECT
  STDDEV_SAMP(duration_days) AS sd_nitrate_prescription_days
FROM (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON a.hadm_id = pr.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND LOWER(pr.drug) LIKE '%nitrate%'
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) > 0
);