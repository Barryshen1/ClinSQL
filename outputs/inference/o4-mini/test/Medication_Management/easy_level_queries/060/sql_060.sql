SELECT
  MAX(duration_days) AS longest_ace_inhibitor_duration_days
FROM (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    DATE_DIFF(
      DATE(pr.stoptime),
      DATE(pr.starttime),
      DAY
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON pt.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON a.subject_id = pr.subject_id
      AND a.hadm_id    = pr.hadm_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 38 AND 48
    -- Filter to prescriptions likely to be ACE inhibitors by drug name
    AND LOWER(pr.drug) LIKE '%pril%'
    -- Ensure valid time windows
    AND pr.starttime IS NOT NULL
    AND pr.stoptime  IS NOT NULL
    AND DATE(pr.stoptime) > DATE(pr.starttime)
);