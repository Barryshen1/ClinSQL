WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 56
),
PrescriptionInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug IN ('hydralazine', 'isosorbide dinitrate')
),
CombinedInfo AS (
  SELECT
    pi.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime
  FROM PatientInfo AS pi
  JOIN PrescriptionInfo AS pr
    ON pi.subject_id = pr.subject_id
)
SELECT
  drug,
  MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_duration_days
FROM CombinedInfo
GROUP BY
  drug;