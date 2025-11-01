WITH pop_stays AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 62 AND 72
),
hr_stays AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY ce.stay_id
),
mi_hadm AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' THEN 1 
          ELSE 0 
        END) AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT
  CASE 
    WHEN mean_hr < 60 THEN '<60'
    WHEN mean_hr BETWEEN 60 AND 99 THEN '60-99'
    WHEN mean_hr BETWEEN 100 AND 119 THEN '100-119'
    WHEN mean_hr >= 120 THEN '>=120'
  END AS hr_category,
  COUNT(*) AS count_stays,
  AVG(COALESCE(mi.has_mi, 0)) * 100 AS percent_with_mi
FROM pop_stays ps
INNER JOIN hr_stays hr ON ps.stay_id = hr.stay_id
LEFT JOIN mi_hadm mi ON ps.hadm_id = mi.hadm_id
GROUP BY hr_category
ORDER BY 
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;