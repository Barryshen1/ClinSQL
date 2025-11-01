WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),
Diagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%diabetes%'
    OR di.long_title LIKE '%heart failure%'
),
MedicationInitiation AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime AS initiation_time,
    p.drug AS medication_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug IN ('metformin', 'insulin', 'glipizide', 'beta-blocker', 'metoprolol', 'carvedilol', 'lisinopril', 'losartan', 'sacubitril/valsartan', 'furosemide', 'bumetanide')
),
TimeWindows AS (
  SELECT
    mi.subject_id,
    mi.hadm_id,
    mi.initiation_time,
    mi.medication_name,
    a.admittime,
    CASE
      WHEN mi.initiation_time BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR) THEN 'First 48h'
      WHEN mi.initiation_time BETWEEN DATETIME_SUB(DATETIME_ADD(a.admittime, INTERVAL 48 HOUR), INTERVAL 12 HOUR) AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR) THEN 'Last 12h'
      ELSE 'Other'
    END AS time_window
  FROM
    MedicationInitiation AS mi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON mi.hadm_id = a.hadm_id
),
CohortMedicationInitiation AS (
  SELECT
    mi.subject_id,
    mi.hadm_id,
    mi.initiation_time,
    mi.medication_name,
    tw.time_window
  FROM
    MedicationInitiation AS mi
  JOIN
    TimeWindows AS tw
    ON mi.subject_id = tw.subject_id AND mi.hadm_id = tw.hadm_id AND mi.initiation_time = tw.initiation_time
  WHERE
    mi.subject_id IN (SELECT subject_id FROM PatientCohort)
    AND mi.hadm_id IN (SELECT hadm_id FROM Diagnosis)
    AND tw.time_window IN ('First 48h', 'Last 12h')
)
SELECT
  medication_name,
  time_window,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT subject_id) * 100.0 / (SELECT COUNT(DISTINCT subject_id) FROM PatientCohort) AS initiation_rate_percent
FROM
  CohortMedicationInitiation
GROUP BY
  medication_name,
  time_window
ORDER BY
  medication_name,
  time_window;