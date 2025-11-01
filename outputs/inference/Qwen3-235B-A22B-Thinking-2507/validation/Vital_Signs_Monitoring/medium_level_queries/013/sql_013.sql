WITH patient_stays AS (
  SELECT 
    icustays.stay_id,
    icustays.hadm_id,
    icustays.subject_id,
    icustays.intime,
    patients.anchor_age,
    patients.anchor_year,
    patients.gender,
    patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'M'
    AND patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) BETWEEN 51 AND 61
),

spo2_measurements AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN patient_stays ps ON ce.stay_id = ps.stay_id
  WHERE ce.itemid = 220277  -- SpO2 itemid
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime BETWEEN ps.intime AND DATETIME_ADD(ps.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),

aki_status AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN valuenum >= 2.0 THEN 1 ELSE 0 END) AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 50912  -- Creatinine itemid
    AND valuenum IS NOT NULL
    AND valuenum > 0
  GROUP BY hadm_id
),

combined_data AS (
  SELECT 
    ps.stay_id,
    ps.hadm_id,
    sm.avg_spo2,
    CASE 
      WHEN sm.avg_spo2 < 90 THEN '<90'
      WHEN sm.avg_spo2 <= 92 THEN '90-92'
      WHEN sm.avg_spo2 <= 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_category,
    COALESCE(aks.has_aki, 0) AS has_aki
  FROM patient_stays ps
  LEFT JOIN spo2_measurements sm ON ps.stay_id = sm.stay_id
  LEFT JOIN aki_status aks ON ps.hadm_id = aks.hadm_id
)

SELECT 
  spo2_category,
  COUNT(*) AS patient_count,
  AVG(has_aki) AS aki_rate
FROM combined_data
WHERE spo2_category IS NOT NULL
GROUP BY spo2_category
ORDER BY 
  CASE spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    ELSE 4
  END;