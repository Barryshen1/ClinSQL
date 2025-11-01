WITH PrescriptionDuration AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug = 'digoxin'
), DurationCalculation AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    pd.starttime,
    pd.stoptime,
    pd.drug,
    -- Calculate duration in days
    DATE_DIFF(pd.stoptime, pd.starttime, DAY) AS duration_days
  FROM
    PrescriptionDuration AS pd
  WHERE
    pd.stoptime IS NOT NULL
)
SELECT
  AVG(dc.duration_days) AS average_duration_days
FROM
  DurationCalculation AS dc
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON dc.subject_id = pat.subject_id
WHERE
  pat.gender = 'M' AND pat.anchor_age BETWEEN 66 AND 76;