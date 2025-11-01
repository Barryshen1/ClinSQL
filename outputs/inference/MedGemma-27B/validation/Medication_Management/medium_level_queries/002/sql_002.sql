WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 59 AND 69
), PatientAdmissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
), MedicationOrders AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    p.prescriptions.drug AS medication_name,
    p.prescriptions.route AS medication_route,
    p.prescriptions.starttime AS order_time,
    p.prescriptions.stoptime AS order_stop_time
  FROM
    PatientAdmissions AS pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON pa.subject_id = p.subject_id AND pa.hadm_id = p.hadm_id
  WHERE
    p.prescriptions.drug LIKE '%GLP-1%'
    AND p.prescriptions.route LIKE '%inject%'
), First48hOrders AS (
  SELECT
    mo.subject_id,
    mo.hadm_id,
    mo.medication_name,
    mo.medication_route,
    mo.order_time
  FROM
    MedicationOrders AS mo
  WHERE
    mo.order_time BETWEEN mo.admittime AND TIMESTAMP_ADD(mo.admittime, INTERVAL 48 HOUR)
), Final12hOrders AS (
  SELECT
    mo.subject_id,
    mo.hadm_id,
    mo.medication_name,
    mo.medication_route,
    mo.order_time
  FROM
    MedicationOrders AS mo
  WHERE
    mo.order_time BETWEEN TIMESTAMP_SUB(mo.dischtime, INTERVAL 12 HOUR) AND mo.dischtime
), First48hCount AS (
  SELECT
    COUNT(DISTINCT subject_id) AS count_first48h
  FROM
    First48hOrders
), Final12hCount AS (
  SELECT
    COUNT(DISTINCT subject_id) AS count_final12h
  FROM
    Final12hOrders
), TotalPatients AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients
  FROM
    PatientAdmissions
)
SELECT
  f48.count_first48h,
  f12.count_final12h,
  f48.count_first48h - f12.count_final12h AS absolute_difference
FROM
  First48hCount AS f48,
  Final12hCount AS f12,
  TotalPatients AS tp;