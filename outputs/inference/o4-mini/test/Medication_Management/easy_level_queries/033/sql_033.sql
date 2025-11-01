SELECT
  AVG(duration_days) AS avg_arb_duration_days
FROM (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON pr.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pr.subject_id = a.subject_id
   AND pr.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(pr.drug) LIKE '%sartan%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- ensure the prescription was during the inpatient stay
    AND pr.starttime >= a.admittime
    AND pr.stoptime <= a.dischtime
    -- require a positive duration
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) > 0
)
;