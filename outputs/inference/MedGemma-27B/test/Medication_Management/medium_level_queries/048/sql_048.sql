WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
    AND d.icd_code IN ('I50', 'I11', 'I13', 'I10') -- Heart failure codes
),
InsulinTypes AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    starttime,
    CASE
      WHEN route = 'Subcutaneous' THEN 'Basal'
      WHEN route = 'Intravenous' AND dose_unit_rx = 'unit' THEN 'Bolus'
      WHEN route = 'Intravenous' AND dose_unit_rx = 'unit/hr' THEN 'Basal-Bolus'
      WHEN route = 'Subcutaneous' AND frequency LIKE '%sliding scale%' THEN 'Sliding-Scale'
      ELSE 'Other'
    END AS insulin_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    drug LIKE '%insulin%'
),
TimePeriods AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    starttime,
    CASE
      WHEN starttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 48 HOUR) THEN 'First 48h'
      WHEN starttime BETWEEN TIMESTAMP_ADD(intime, INTERVAL 48 HOUR) AND TIMESTAMP_ADD(outtime, INTERVAL -48 HOUR) THEN 'Final 48h'
      ELSE 'Other'
    END AS time_period
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.hadm_id = i.hadm_id
),
Transitions AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    drug LIKE '%insulin%'
    AND time_period = 'First 48h'
  INTERSECT
  SELECT
    subject_id,
    hadm_id,
    stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    drug LIKE '%insulin%'
    AND time_period = 'Final 48h'
),
First48h AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    insulin_type
  FROM
    InsulinTypes
  WHERE
    time_period = 'First 48h'
),
Final48h AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    insulin_type
  FROM
    InsulinTypes
  WHERE
    time_period = 'Final 48h'
)
SELECT
  insulin_type,
  COUNT(DISTINCT CASE WHEN time_period = 'First 48h' THEN subject_id END) AS count_first_48h,
  COUNT(DISTINCT CASE WHEN time_period = 'Final 48h' THEN subject_id END) AS count_final_48h,
  COUNT(DISTINCT CASE WHEN time_period = 'First 48h' THEN subject_id END) / COUNT(DISTINCT subject_id) AS pct_first_48h,
  COUNT(DISTINCT CASE WHEN time_period = 'Final 48h' THEN subject_id END) / COUNT(DISTINCT subject_id) AS pct_final_48h,
  COUNT(DISTINCT subject;