SELECT
  AVG(duration_days) AS avg_prescription_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON pr.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON pr.subject_id = a.subject_id
    AND pr.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      LOWER(pr.drug) LIKE '%spironolactone%'
      OR LOWER(pr.drug) LIKE '%eplerenone%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
);