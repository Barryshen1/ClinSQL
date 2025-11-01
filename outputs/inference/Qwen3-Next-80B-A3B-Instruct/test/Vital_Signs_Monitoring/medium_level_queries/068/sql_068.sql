WITH first_map AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS map_value,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Mean Arterial Pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
icu_stays_with_map AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    fm.map_value
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN first_map fm
    ON i.stay_id = fm.stay_id
  WHERE fm.rn = 1
),
stroke_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%stroke%'
     OR (di.icd_version = 9 AND di.icd_code BETWEEN '430' AND '438')
     OR (di.icd_version = 10 AND di.icd_code BETWEEN 'I60' AND 'I69')
),
patients_filtered AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),
final_data AS (
  SELECT 
    ism.stay_id,
    ism.map_value,
    CASE 
      WHEN ism.map_value < 65 THEN '<65'
      WHEN ism.map_value BETWEEN 65 AND 74 THEN '65-74'
      WHEN ism.map_value BETWEEN 75 AND 84 THEN '75-84'
      WHEN ism.map_value >= 85 THEN '>=85'
    END AS map_category,
    CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_stroke
  FROM icu_stays_with_map ism
  JOIN patients_filtered pf
    ON ism.subject_id = pf.subject_id
  LEFT JOIN stroke_diagnoses sd
    ON ism.hadm_id = sd.hadm_id
)
SELECT 
  map_category,
  COUNT(*) AS patient_count,
  SUM(has_stroke) AS stroke_count,
  ROUND(SUM(has_stroke) * 100.0 / COUNT(*), 2) AS stroke_rate_percent
FROM final_data
WHERE map_category IS NOT NULL
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;