WITH spo2_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%spo2%'
),

-- Step 2: Identify the ICU stays for female patients aged 38-48
female_stays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON a.subject_id = ic.subject_id
      AND a.hadm_id = ic.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

-- Step 3: Compute per-stay mean SpO2
per_stay_spo2 AS (
  SELECT
    fs.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM
    female_stays fs
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON fs.subject_id = ce.subject_id
      AND fs.hadm_id    = ce.hadm_id
      AND fs.stay_id    = ce.stay_id
    JOIN spo2_items di
      ON ce.itemid = di.itemid
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    fs.stay_id
)

-- Step 4: Compute the percentile of stays with mean_spo2 <= 92
SELECT
  COUNTIF(mean_spo2 <= 92) * 1.0 / COUNT(*) AS percentile_leq_92
FROM
  per_stay_spo2;