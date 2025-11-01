WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%o2 saturation%'
),

-- Step 2: Get female ICU stays aged 38-48
female_stays AS (
  SELECT icu.stay_id, icu.subject_id, icu.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
),

-- Step 3: Calculate per-stay mean SpO2
stay_spo2 AS (
  SELECT
    fs.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM female_stays fs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.subject_id = ce.subject_id
   AND fs.hadm_id = ce.hadm_id
   AND fs.stay_id = ce.stay_id
  JOIN spo2_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 100 -- plausible SpO2 values
  GROUP BY fs.stay_id
)

-- Step 4: Calculate percentile for mean SpO2 ≤ 92%
SELECT
  COUNTIF(mean_spo2 <= 92) / COUNT(*) AS percentile_le_92
FROM stay_spo2;