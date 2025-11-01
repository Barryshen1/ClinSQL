WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age >= 86
    AND p.anchor_age <= 96
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
    ON p.subject_id = d2.subject_id
    AND d2.icd_code IN ('I50', 'I11', 'I13', 'I10', 'I12', 'I50', 'I11', 'I13', 'I10', 'I12') -- Heart Failure codes
),
MedicationEvents AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.charttime,
    p.medication,
    CASE
      WHEN p.medication LIKE '%insulin%' THEN 'Insulin'
      WHEN p.medication LIKE '%metformin%' OR p.medication LIKE '%sulfonylurea%' OR p.medication LIKE '%thiazolidinedione%' OR p.medication LIKE '%sgl%' OR p.medication LIKE '%dpp%' THEN 'Oral Agents'
      ELSE 'Other'
    END AS medication_class
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS p
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
EarlyMedication AS (
  SELECT
    subject_id,
    hadm_id,
    medication_class,
    MIN(charttime) AS first_med_time
  FROM MedicationEvents
  WHERE
    charttime BETWEEN '2008-01-01 00:00:00' AND '2008-01-01 12:00:00'
  GROUP BY
    subject_id,
    hadm_id,
    medication_class
),
LateMedication AS (
  SELECT
    subject_id,
    hadm_id,
    medication_class,
    MAX(charttime) AS last_med_time
  FROM MedicationEvents
  WHERE
    charttime BETWEEN '2008-01-01 00:00:00' AND '2008-01-01 12:00:00'
  GROUP BY
    subject_id,
    hadm_id,
    medication_class
),
EarlyLateTransitions AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.medication_class AS early_class,
    l.medication_class AS late_class
  FROM EarlyMedication AS e
  JOIN LateMedication AS l
    ON e.subject_id = l.subject_id AND e.hadm_id = l.hadm_id
  WHERE
    e.first_med_time < l.last_med_time
)
SELECT
  'Insulin' AS medication_class,
  COUNT(DISTINCT CASE WHEN early_class = 'Insulin' THEN subject_id END) / COUNT(DISTINCT subject_id) AS early_rate,
  COUNT(DISTINCT CASE WHEN late_class = 'Insulin' THEN subject_id END) / COUNT(DISTINCT subject_id) AS late_rate,
  COUNT(DISTINCT CASE WHEN early_class = 'Insulin' AND late_class = 'Insulin' THEN subject_id END) / COUNT(DISTINCT CASE WHEN early_class = 'Insulin' THEN subject_id END) AS early_to_late_transition
FROM EarlyLateTransitions;