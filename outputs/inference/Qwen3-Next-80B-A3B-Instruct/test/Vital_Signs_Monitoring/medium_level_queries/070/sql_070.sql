WITH icu_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.intime,
    i.outtime,
    CASE 
      WHEN di.icd_code LIKE 'N17%' OR LOWER(ddi.long_title) LIKE '%acute kidney injury%' 
      THEN 1 
      ELSE 0 
    END AS has_aki
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON i.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi 
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 90 AND 100
),

-- Deduplicate AKI flag per stay: if any diagnosis exists, flag as 1
-- Also carry forward intime for time window filtering
icu_patients_aki AS (
  SELECT 
    stay_id,
    MAX(has_aki) AS has_aki,
    MAX(intime) AS intime  -- intime is functionally dependent on stay_id; use MAX to include in aggregation
  FROM icu_patients
  GROUP BY stay_id
),

-- Extract SpO2 measurements within first 24 hours of ICU stay
spo2_first24 AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS spo2_value,
    ipa.has_aki
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_patients_aki ipa 
    ON ce.stay_id = ipa.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE di.label = 'SpO2'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ipa.intime
    AND ce.charttime < DATETIME_ADD(ipa.intime, INTERVAL 24 HOUR)
)

-- Final aggregation by SpO2 category
SELECT
  CASE 
    WHEN spo2_value < 90 THEN '<90'
    WHEN spo2_value BETWEEN 90 AND 92 THEN '90-92'
    WHEN spo2_value BETWEEN 93 AND 95 THEN '93-95'
    WHEN spo2_value > 95 THEN '>95'
  END AS spo2_category,
  COUNT(*) AS N,
  AVG(spo2_value) AS mean,
  PERCENTILE_CONT(spo2_value, 0.5) AS median,
  PERCENTILE_CONT(spo2_value, 0.25) AS q1,
  PERCENTILE_CONT(spo2_value, 0.75) AS q3,
  AVG(has_aki) AS aki_rate
FROM spo2_first24
GROUP BY spo2_category
ORDER BY 
  CASE spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
  END;