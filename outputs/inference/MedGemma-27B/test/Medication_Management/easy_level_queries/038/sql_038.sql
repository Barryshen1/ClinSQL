WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 41
),
PrescriptionDuration AS (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    (
      DATE_DIFF(pr.stoptime, pr.starttime, DAY)
    ) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN PatientInfo AS pi
    ON pr.subject_id = pi.subject_id
  WHERE
    pr.drug = 'digoxin'
),
AgeGroupFilter AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 36 AND 46
)
SELECT
  PERCENTILE_CONT(0.25, duration_days) AS q1,
  PERCENTILE_CONT(0.75, duration_days) AS q3,
  q3 - q1 AS IQR
FROM PrescriptionDuration AS pd
JOIN AgeGroupFilter AS agf
  ON pd.subject_id = agf.subject_id;