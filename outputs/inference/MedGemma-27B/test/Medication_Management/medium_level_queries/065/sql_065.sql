WITH PatientCohort AS (
  -- Identify patients meeting the age and diagnosis criteria
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes (ICD-10)
    AND d.icd_code IN ('I50', 'I11', 'I13', 'I10') -- Heart Failure codes (ICD-10)
),
MedicationEvents AS (
  -- Extract relevant medication events (insulin and oral agents)
  SELECT
    h.subject_id,
    h.hadm_id,
    h.charttime,
    m.medication,
    m.drug_type,
    CASE
      WHEN m.medication LIKE '%insulin%' THEN 'Insulin'
      WHEN m.drug_type = 'Oral' THEN 'Oral Agent'
      ELSE NULL
    END AS medication_type
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS h
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS m
    ON h.emar_id = m.emar_id
  WHERE
    h.subject_id IN (SELECT subject_id FROM PatientCohort)
    AND (m.medication LIKE '%insulin%' OR m.drug_type = 'Oral')
),
TimeWindows AS (
  -- Define the time windows for analysis
  SELECT
    subject_id,
    hadm_id,
    charttime,
    medication_type,
    CASE
      WHEN charttime BETWEEN 0 AND 48 THEN '0-48h'
      WHEN charttime > (SELECT MAX(a.dischtime) FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a WHERE a.subject_id = subject_id AND a.hadm_id = hadm_id) - INTERVAL 72 HOUR THEN 'Final 72h'
      ELSE NULL
    END AS time_window
  FROM MedicationEvents
),
InitiationRates AS (
  -- Calculate initiation rates for each medication type and time window
  SELECT
    medication_type,
    time_window,
    COUNT(DISTINCT subject_id) AS initiation_count
  FROM TimeWindows
  WHERE
    time_window IS NOT NULL
  GROUP BY
    medication_type,
    time_window
),
NetChange AS (
  -- Calculate net change in medication use (this part is complex and requires more detailed data)
  -- Placeholder: This requires tracking medication start/stop times and dosages, which is beyond the scope of the provided tables.
  -- A more accurate calculation would involve analyzing prescriptions or pharmacy data over time.
  SELECT
    medication_type,
    time_window,
    0 AS net_change -- Placeholder value
  FROM TimeWindows
  WHERE
    time_window IS NOT NULL
  GROUP BY
    medication_type,
    time_window
)
-- Final result combining initiation rates and net change
SELECT
  ir.medication_type,
  ir.time_window,
  ir.initiation_count,
  nc.net_change
FROM InitiationRates AS ir
LEFT JOIN NetChange AS nc
  ON ir.medication_type = nc.medication_type AND ir.time_window = nc.time_window;