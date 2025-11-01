SELECT
  STDDEV(LOS_days) AS sd_los_days
FROM (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND pr.icd_version = 9
    AND pr.icd_code IN ('3995', '5498') -- 39.95 hemodialysis, 54.98 peritoneal dialysis
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
);