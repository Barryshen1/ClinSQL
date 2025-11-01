WITH
-- Get male patients with pneumonia admissions
pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND d.icd_code IN (
      'J18.9', 'J18.0', 'J18.1', 'J18.2', 'J18.8', -- Removed duplicate 'J18.9'
      '486', '485', '482.9', '482.81', '482.82', '482.83', '482.84', '482.89', '482.30', '482.31', '482.32', '482.39', '482.40', '482.41', '482.42', '482.49', '482.9'
    )
    AND d.icd_version IN (9, 10) -- Fixed: changed from strings to integers
),

-- Get glucose measurements near discharge
glucose_at_discharge AS (
  SELECT
    p.hadm_id,
    le.valuenum AS glucose_value,
    le.charttime,
    p.dischtime,
    -- Calculate time difference between glucose measurement and discharge
    TIMESTAMP_DIFF(p.dischtime, le.charttime, HOUR) AS hours_before_discharge
  FROM
    pneumonia_admissions p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON p.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Glucose' -- or use itemid directly if known (e.g., 50809 for glucose)
    AND le.charttime <= p.dischtime
    AND TIMESTAMP_DIFF(p.dischtime, le.charttime, HOUR) <= 24 -- Within 24 hours of discharge
),

-- Get the last glucose measurement before discharge for each admission
last_glucose_before_discharge AS (
  SELECT
    hadm_id,
    glucose_value,
    hours_before_discharge
  FROM (
    SELECT
      hadm_id,
      glucose_value,
      hours_before_discharge,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY hours_before_discharge ASC) AS rn
    FROM
      glucose_at_discharge
  )
  WHERE
    rn = 1 -- Only the last measurement before discharge
)

-- Calculate the 75th percentile of glucose values
SELECT
  PERCENTILE_CONT(glucose_value, 0.75) OVER() AS percentile_75_glucose
FROM
  last_glucose_before_discharge
LIMIT 1;