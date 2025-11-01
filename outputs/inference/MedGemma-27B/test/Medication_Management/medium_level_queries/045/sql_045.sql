WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 59
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
      WHERE
        d2.subject_id = p.subject_id
        AND d2.icd_code IN ('I50', 'I11', 'I13', 'I10') -- Heart Failure codes
    )
),
MedicationEvents AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.charttime,
    CASE
      WHEN LOWER(m.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(m.medication) LIKE '%metformin%' OR LOWER(m.medication) LIKE '%glipizide%' OR LOWER(m.medication) LIKE '%glyburide%' THEN 'Oral Agent'
      ELSE 'Other'
    END AS medication_type,
    h.pharmacy_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS h
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS m
    ON h.emar_id = m.emar_id
  WHERE
    h.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND h.charttime BETWEEN TIMESTAMP_SUB(a.admittime, INTERVAL 12 HOUR) AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON h.hadm_id = a.hadm_id
),
TimeWindows AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    medication_type,
    CASE
      WHEN charttime BETWEEN TIMESTAMP_SUB(a.admittime, INTERVAL 12 HOUR) AND TIMESTAMP_ADD(a.admittime, INTERVAL 0 HOUR) THEN 'First 12 Hours'
      WHEN charttime BETWEEN TIMESTAMP_SUB(a.admittime, INTERVAL 48 HOUR) AND TIMESTAMP_ADD(a.admittime, INTERVAL 0 HOUR) THEN 'Final 48 Hours'
      ELSE 'Other'
    END AS time_window
  FROM MedicationEvents
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON MedicationEvents.hadm_id = a.hadm_id
  WHERE
    time_window IN ('First 12 Hours', 'Final 48 Hours')
),
Prevalence AS (
  SELECT
    time_window,
    medication_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM TimeWindows
  GROUP BY
    time_window,
    medication_type
)
SELECT
  time_window,
  medication_type,
  patient_count
FROM Prevalence
ORDER BY
  time_window,
  medication_type;