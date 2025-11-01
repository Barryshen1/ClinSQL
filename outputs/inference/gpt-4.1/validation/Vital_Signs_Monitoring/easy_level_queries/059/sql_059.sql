WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),

-- Step 2: Filter male patients aged 77-87
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),

-- Step 3: Get first SpO2 per admission
first_spo2 AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    MIN(ce.charttime) AS first_spo2_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN eligible_patients ep ON adm.subject_id = ep.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON adm.subject_id = ce.subject_id
    AND adm.hadm_id = ce.hadm_id
  JOIN spo2_items si ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= adm.admittime
  GROUP BY adm.subject_id, adm.hadm_id
),

-- Step 4: Get the SpO2 value at that time
first_spo2_values AS (
  SELECT
    fs.subject_id,
    fs.hadm_id,
    ce.valuenum AS spo2_value
  FROM first_spo2 fs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.subject_id = ce.subject_id
    AND fs.hadm_id = ce.hadm_id
    AND ce.charttime = fs.first_spo2_time
  JOIN spo2_items si ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
)

-- Step 5: Calculate standard deviation
SELECT
  STDDEV_SAMP(spo2_value) AS stddev_first_spo2
FROM first_spo2_values;