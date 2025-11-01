WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%oxygen saturation%'
     OR LOWER(abbreviation) LIKE '%spo2%'
),
patient_admissions AS (
  -- admissions for men aged 77-87
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),
first_spo2_per_admission AS (
  -- find the first SpO2 chart event on/after hospital admit time for each admission
  SELECT
    pa.hadm_id,
    pa.subject_id,
    c.charttime,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY c.charttime) AS rn
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
    ON pa.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  JOIN spo2_items di
    ON c.itemid = di.itemid
  WHERE c.charttime >= pa.admittime
    AND c.valuenum IS NOT NULL
    -- plausible SpO2 range in percent to reduce artifacts; adjust if desired
    AND c.valuenum BETWEEN 50 AND 100
)
SELECT
  COUNT(valuenum) AS n_admissions_with_spo2,
  ROUND(AVG(valuenum), 2) AS mean_first_spo2,
  ROUND(STDDEV_POP(valuenum), 2) AS sd_first_spo2_population
FROM first_spo2_per_admission
WHERE rn = 1;