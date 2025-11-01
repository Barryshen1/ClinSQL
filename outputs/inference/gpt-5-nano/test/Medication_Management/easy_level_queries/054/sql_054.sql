SELECT AVG(duration_days) AS avg_duration_days
FROM (
  SELECT
    p.subject_id,
    p.hadm_id,
    (TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON p.subject_id = pat.subject_id
  WHERE LOWER(p.drug) LIKE '%digoxin%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND UPPER(pat.gender) = 'MALE'
    AND pat.anchor_age BETWEEN 66 AND 76
) AS src;