WITH spo2_items AS (
  -- identify SpO2 / oxygen saturation related itemids in ICU d_items
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%o2sat%'
     OR LOWER(label) LIKE '%oxygen saturation%'
     OR LOWER(label) LIKE '%oxy sat%'
),

aki_hadms AS (
  -- admissions with AKI diagnosis (text-based matching on diagnosis description)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute kidney%'
     OR LOWER(d.long_title) LIKE '%acute renal%'
),

stay_spo2 AS (
  -- per-ICU-stay average SpO2 in the first 48 hours of the ICU stay
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(ce.valuenum) AS avg_spo2,
    COUNT(1) AS n_spo2_measurements
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = icu.subject_id
   AND ce.stay_id = icu.stay_id
  JOIN spo2_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= icu.intime
    AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),

filtered_stays AS (
  -- restrict to male patients aged 51-61 and categorize avg_spo2
  SELECT
    s.*,
    CASE
      WHEN s.avg_spo2 < 90 THEN '<90'
      WHEN s.avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN s.avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_category
  FROM stay_spo2 s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
)

SELECT
  fs.spo2_category,
  COUNT(1) AS n_stays,
  SUM(CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_aki,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(1)), 4) AS aki_rate
FROM filtered_stays fs
LEFT JOIN aki_hadms a
  ON fs.hadm_id = a.hadm_id
GROUP BY fs.spo2_category
ORDER BY
  -- put categories in clinically meaningful order
  CASE fs.spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
    ELSE 5
  END;