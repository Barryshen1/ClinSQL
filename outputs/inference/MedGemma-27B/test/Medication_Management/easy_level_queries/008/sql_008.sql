WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 69 -- Assuming the patient ID is 69, replace if needed
),
AspirinPrescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pr.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.subject_id = 69 -- Assuming the patient ID is 69, replace if needed
    AND pr.drug = 'aspirin'
    AND pr.starttime IS NOT NULL
),
P2Y12Prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pr.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.subject_id = 69 -- Assuming the patient ID is 69, replace if needed
    AND pr.drug IN ('clopidogrel', 'prasugrel', 'ticagrelor')
    AND pr.starttime IS NOT NULL
),
CombinedPrescriptions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.starttime AS aspirin_starttime,
    a.stoptime AS aspirin_stoptime,
    b.starttime AS p2y12_starttime,
    b.stoptime AS p2y12_stoptime
  FROM
    AspirinPrescriptions AS a
  JOIN
    P2Y12Prescriptions AS b
    ON a.subject_id = b.subject_id
    AND a.hadm_id = b.hadm_id
  WHERE
    a.starttime <= b.starttime
    AND b.starttime <= a.stoptime
),
DurationCalculation AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN aspirin_stoptime IS NULL THEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), aspirin_starttime, DAY)
      ELSE TIMESTAMP_DIFF(aspirin_stoptime, aspirin_starttime, DAY)
    END AS aspirin_duration
  FROM
    CombinedPrescriptions
)
SELECT
  AVG(aspirin_duration)
FROM
  DurationCalculation;