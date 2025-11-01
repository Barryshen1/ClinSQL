WITH patients_45_55_male AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM icu.intime) - p.anchor_year + p.anchor_age) BETWEEN 45 AND 55
),

hf_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I50%'
    AND di.icd_version = 10
),

cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
  INNER JOIN patients_45_55_male p ON icu.subject_id = p.subject_id
  INNER JOIN hf_diagnoses hf ON icu.hadm_id = hf.hadm_id
),

vital_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE label IN ('Heart Rate', 'Mean Blood Pressure', 'Respiratory Rate')
),

vitals_72h AS (
  SELECT ce.stay_id, ce.itemid, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN vital_items vi ON ce.itemid = vi.itemid
  INNER JOIN cohort c ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
),

abnormal_vitals AS (
  SELECT 
    stay_id,
    SUM(CASE WHEN itemid = (SELECT itemid FROM vital_items WHERE label = 'Heart Rate') AND valuenum > 100 THEN 1 ELSE 0 END) AS hr_tach_count,
    SUM(CASE WHEN itemid = (SELECT itemid FROM vital_items WHERE label = 'Mean Blood Pressure') AND valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN itemid = (SELECT itemid FROM vital_items WHERE label = 'Respiratory Rate') AND valuenum > 20 THEN 1 ELSE 0 END) AS rr_tach_count
  FROM vitals_72h
  GROUP BY stay_id
),

instability_score AS (
  SELECT 
    av.stay_id,
    av.hr_tach_count + av.map_low_count + av.rr_tach_count AS composite_score,
    av.hr_tach_count,
    av.map_low_count,
    av.rr_tach_count,
    c.los AS icu_los,
    a.hospital_expire_flag
  FROM abnormal_vitals av
  INNER JOIN cohort c ON av.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON c.hadm_id = a.hadm_id
),

percentiles AS (
  SELECT 
    APPROX_QUANTILES(composite_score, 100)[OFFSET(99)] AS p99_score
  FROM instability_score
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY composite_score) AS score_quartile
  FROM instability_score
),

top_quartile AS (
  SELECT *
  FROM quartiles
  WHERE score_quartile = 4
),

summary_stats AS (
  SELECT
    'top_quartile' AS group_name,
    AVG(CASE WHEN hr_tach_count > 0 THEN 1.0 ELSE 0.0 END) AS avg_tachycardia,
    AVG(CASE WHEN map_low_count > 0 THEN 1.0 ELSE 0.0 END) AS avg_map_lt_65,
    AVG(CASE WHEN rr_tach_count > 0 THEN 1.0 ELSE 0.0 END) AS avg_tachypnea,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM top_quartile

  UNION ALL

  SELECT
    'full_cohort' AS group_name,
    AVG(CASE WHEN hr_tach_count > 0 THEN 1.0 ELSE 0.0 END) AS avg_tachycardia,
    AVG(CASE WHEN map_low_count > 0 THEN 1.0 ELSE 0.0 END) AS avg_map_lt_65,
    AVG(CASE WHEN rr_tach_count > 0 THEN 1.0 ELSE 0.0 END) AS avg_tachypnea,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM instability_score
)
SELECT * FROM summary_stats;