SELECT
  AVG(duration_days) AS avg_warfarin_prescription_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.subject_id = a.subject_id
    AND pr.hadm_id = a.hadm_id
  WHERE
    LOWER(pr.drug) LIKE '%warfarin%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
);