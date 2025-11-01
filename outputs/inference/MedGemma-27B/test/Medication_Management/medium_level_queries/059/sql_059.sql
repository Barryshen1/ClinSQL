WITH PatientCohort AS (
  -- Select subject_id for patients meeting the criteria
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 65
    AND d.icd_code IN ('E11', 'E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8') -- T2DM codes
    AND d.icd_code IN ('I50', 'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.7', 'I50.8') -- HF codes
),
MedicationInitiation AS (
  -- Identify medication initiation events within the first 48 hours and final 24 hours
  SELECT
    p.subject_id,
    m.medication,
    m.charttime,
    CASE
      WHEN m.charttime BETWEEN (SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE subject_id = p.subject_id) AND DATETIME_ADD((SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE subject_id = p.subject_id), INTERVAL 48 HOUR) THEN 'First 48h'
      WHEN m.charttime BETWEEN DATETIME_SUB((SELECT MAX(outtime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE subject_id = p.subject_id), INTERVAL 24 HOUR) AND (SELECT MAX(outtime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE subject_id = p.subject_id) THEN 'Final 24h'
      ELSE NULL
    END AS time_window,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id, m.medication ORDER BY m.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS m
  JOIN PatientCohort AS p ON m.subject_id = p.subject_id
  WHERE
    m.medication IN ('Metformin', 'Sulfonylurea', 'Insulin', 'Beta-blocker', 'ACE inhibitor', 'ARB', 'ARNI', 'Loop diuretic') -- List of medications of interest
    AND m.charttime IS NOT NULL
),
InitiationCounts AS (
  -- Count the number of patients initiating each medication in each time window
  SELECT
    medication,
    time_window,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM MedicationInitiation
  WHERE
    rn = 1 -- Only consider the first initiation event
  GROUP BY
    medication,
    time_window
),
TotalPatients AS (
  -- Count the total number of patients in the cohort
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients
  FROM PatientCohort
)
-- Final result: Calculate initiation percentage and absolute difference
SELECT
  ic.medication,
  ic.time_window,
  (ic.patient_count / tp.total_patients) * 100 AS initiation_percentage,
  ic.patient_count AS absolute_difference_pp
FROM InitiationCounts AS ic
CROSS JOIN TotalPatients AS tp
ORDER BY
  ic.medication,
  ic.time_window;