WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 89 -- Assuming the patient's subject_id is 89
), Prescriptions AS (
  SELECT
    p.subject_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN
    PatientInfo AS pi
    ON p.subject_id = pi.subject_id
  WHERE
    p.drug LIKE '%aspirin%'
    AND p.drug LIKE '%clopidogrel%'
    AND p.drug LIKE '%DAPT%'
), Duration AS (
  SELECT
    subject_id,
    TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM
    Prescriptions
)
SELECT
  MAX(duration_days) AS max_dapt_duration
FROM
  Duration
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 84 AND 94
  );