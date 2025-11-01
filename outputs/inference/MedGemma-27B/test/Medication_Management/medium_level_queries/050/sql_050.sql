WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON p.subject_id = diag.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d_diag.long_title LIKE '%diabetes%' -- Using LIKE for simplicity, consider specific codes like E11.9
    AND d_diag.long_title LIKE '%heart failure%' -- Using LIKE for simplicity, consider specific codes like I50.9
),
MedicationEvents AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime AS event_time,
    p.drug AS medication_name,
    p.route,
    p.dose_val_rx,
    p.dose_unit_rx,
    p.drug_type,
    p.stoptime AS stop_time,
    p.status AS order_status
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE p.subject_id IN (SELECT subject_id FROM PatientCohort)
  UNION ALL
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime AS event_time,
    e.medication AS medication_name,
    e.route,
    e.dose_given AS dose_val_rx,;