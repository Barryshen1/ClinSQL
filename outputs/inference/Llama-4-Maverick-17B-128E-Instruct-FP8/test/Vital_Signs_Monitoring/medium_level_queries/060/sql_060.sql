WITH 
sbp_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label LIKE '%Systolic Blood Pressure%' AND param_type = 'Numeric'
),
patient_sbp AS (
  SELECT 
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND ce.itemid IN (SELECT itemid FROM sbp_itemid)
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY p.subject_id, icu.hadm_id, icu.stay_id
),
sbp_category AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    max_sbp,
    CASE 
      WHEN max_sbp < 130 THEN '<130'
      WHEN max_sbp BETWEEN 130 AND 139 THEN '130-139'
      WHEN max_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_cat
  FROM patient_sbp
),
stroke_cases AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%stroke%' AND di.icd_version = 10
),
final AS (
  SELECT 
    sbp_cat,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN hadm_id IN (SELECT hadm_id FROM stroke_cases) THEN 1 ELSE 0 END) AS stroke_count
  FROM sbp_category
  GROUP BY sbp_cat
)
SELECT 
  sbp_cat,
  total_patients,
  ROUND(total_patients * 100 / SUM(total_patients) OVER (), 2) AS percent_patients,
  ROUND(stroke_count * 100 / total_patients, 2) AS stroke_rate
FROM final
ORDER BY sbp_cat;