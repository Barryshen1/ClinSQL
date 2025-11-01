WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 55
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
      WHERE
        d2.subject_id = p.subject_id
        AND d2.icd_code IN ('I50', 'I11', 'I13', 'I10', 'I50', 'I11', 'I13', 'I10') -- Heart failure codes
    )
),
MedicationInitiation AS (
  SELECT
    p.subject_id,
    m.starttime AS initiation_time,
    m.drug AS medication_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS m
  JOIN PatientCohort AS pc
    ON m.subject_id = pc.subject_id
  WHERE
    m.drug LIKE '%semaglutide%'
    OR m.drug LIKE '%dulaglutide%'
    OR m.drug LIKE '%liraglutide%'
    OR m.drug LIKE '%exenatide%'
    OR m.drug LIKE '%lixisenatide%'
    OR m.drug LIKE '%taspoglutide%'
    OR m.drug LIKE '%tirzepatide%'
    AND m.drug_type = 'Drug'
    AND m.route = 'Subcutaneous'
    AND m.starttime IS NOT NULL
),
AdmissionTiming AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
TimeWindow AS (
  SELECT
    mi.subject_id,
    mi.initiation_time,
    at.admittime,
    at.dischtime,
    CASE
      WHEN mi.initiation_time BETWEEN at.admittime AND TIMESTAMP_ADD(at.admittime, INTERVAL 72 HOUR) THEN 'First 72h'
      WHEN mi.initiation_time BETWEEN TIMESTAMP_ADD(at.admittime, INTERVAL 72 HOUR) AND at.dischtime THEN 'Final 72h'
      ELSE 'Other'
    END AS time_window
  FROM MedicationInitiation AS mi
  JOIN AdmissionTiming AS at
    ON mi.subject_id = at.subject_id
  WHERE
    mi.initiation_time >= at.admittime
    AND mi.initiation_time < at.dischtime
)
SELECT
  time_window,
  COUNT(DISTINCT subject_id) AS num_patients,
  COUNT(DISTINCT subject_id) * 100.0 / (
    SELECT
      COUNT(DISTINCT subject_id)
    FROM TimeWindow
  ) AS percentage
FROM TimeWindow
WHERE
  time_window IN ('First 72h', 'Final 72h')
GROUP BY
  time_window
ORDER BY
  time_window;