WITH icu_stays AS (
  SELECT
    icustays.stay_id,
    icustays.hadm_id,
    patients.gender,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON icustays.hadm_id = admissions.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'M'
    AND (anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)) BETWEEN 56 AND 66
),
map_data AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid = 456
    AND valuenum IS NOT NULL
  GROUP BY stay_id
),
stroke_flag AS (
  SELECT
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code BETWEEN '430' AND '438') 
        OR (icd_version = 10 AND icd_code BETWEEN 'I60' AND 'I69') 
      THEN 1 ELSE 0 
    END) AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT
  CASE
    WHEN mean_map < 65 THEN '<65'
    WHEN mean_map >= 65 AND mean_map < 75 THEN '65-74'
    WHEN mean_map >= 75 AND mean_map < 85 THEN '75-84'
    ELSE '>=85'
  END AS map_category,
  COUNT(*) AS patient_count,
  SUM(COALESCE(stroke_flag.has_stroke, 0)) / COUNT(*) AS stroke_rate
FROM icu_stays
JOIN map_data USING (stay_id)
LEFT JOIN stroke_flag ON icu_stays.hadm_id = stroke_flag.hadm_id
GROUP BY map_category
ORDER BY map_category;