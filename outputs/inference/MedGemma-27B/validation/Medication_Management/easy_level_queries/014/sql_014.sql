WITH PatientInfo AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 91
    AND gender = 'F'
), MedicationOrders AS (
  SELECT
    p.subject_id,
    p.starttime,
    p.stoptime,
    p.drug,
    p.dose_val_rx,
    p.dose_unit_rx
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug = 'atorvastatin'
    AND p.dose_val_rx BETWEEN 40 AND 80
    AND p.dose_unit_rx = 'mg'
), PatientMedication AS (
  SELECT
    pi.subject_id,
    mo.starttime,
    mo.stoptime
  FROM
    PatientInfo AS pi
  JOIN
    MedicationOrders AS mo
    ON pi.subject_id = mo.subject_id
)
SELECT
  MIN(DATE_DIFF(stoptime, starttime, DAY)) AS min_duration_days
FROM
  PatientMedication;