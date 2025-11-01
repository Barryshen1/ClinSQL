WITH icu_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

sbp_measurements AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS sbp_valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  JOIN icu_patients ip
    ON ce.stay_id = ip.stay_id
  WHERE di.label = 'Systolic Blood Pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum >= 50 
    AND ce.valuenum <= 300
    AND ce.charttime >= ip.intime 
    AND ce.charttime <= TIMESTAMP_ADD(ip.intime, INTERVAL 48 HOUR)
),

sbp_per_stay AS (
  SELECT 
    s.stay_id,
    AVG(s.sbp_valuenum) AS mean_sbp
  FROM sbp_measurements s
  GROUP BY s.stay_id
  HAVING AVG(s.sbp_valuenum) IS NOT NULL
),

sbp_categories AS (
  SELECT 
    stay_id,
    mean_sbp,
    CASE 
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN mean_sbp >= 160 THEN '>=160'
    END AS sbp_category
  FROM sbp_per_stay
),

mi_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE LOWER(did.long_title) LIKE '%myocardial infarction%'
    OR di.icd_code LIKE '410%'  -- ICD-9
    OR di.icd_code LIKE 'I21%'  -- ICD-10
),

final_analysis AS (
  SELECT 
    sc.sbp_category,
    COUNT(sc.stay_id) AS total_stays,
    SUM(CASE WHEN md.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS mi_count
  FROM sbp_categories sc
  JOIN icu_patients ip ON sc.stay_id = ip.stay_id
  LEFT JOIN mi_diagnoses md ON ip.hadm_id = md.hadm_id
  GROUP BY sc.sbp_category
)

SELECT 
  sbp_category,
  ROUND(100.0 * total_stays / SUM(total_stays) OVER (), 2) AS percent_of_stays,
  ROUND(100.0 * mi_count / total_stays, 2) AS mi_rate_percent
FROM final_analysis
ORDER BY sbp_category;