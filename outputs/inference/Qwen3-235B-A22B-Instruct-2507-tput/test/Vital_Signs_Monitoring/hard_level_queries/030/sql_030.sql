WITH patients_filtered AS (
  SELECT p.subject_id, 
         p.anchor_age, 
         p.anchor_year, 
         p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
),
admissions_filtered AS (
  SELECT a.subject_id, 
         a.hadm_id, 
         a.admittime, 
         a.dischtime, 
         a.hospital_expire_flag,
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 43 AND 53
),
diagnosis_arf AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute respiratory failure%'
     OR d.icd_code IN ('J96.0', 'J96.00', 'J96.01', 'J96.02')
),
icu_stays_with_arf AS (
  SELECT ie.subject_id, 
         ie.hadm_id, 
         ie.stay_id, 
         ie.intime, 
         ie.outtime, 
         ie.los AS icu_los,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  JOIN admissions_filtered a ON ie.hadm_id = a.hadm_id
  JOIN diagnosis_arf d ON ie.hadm_id = d.hadm_id
),
vital_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) IN ('heart rate', 'mean blood pressure', 'respiratory rate', 'spo2')
     OR LOWER(abbreviation) IN ('hr', 'map', 'rr', 'spo2')
),
vitals_first_48h AS (
  SELECT ce.stay_id,
         ce.charttime,
         vi.label,
         ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  JOIN vital_items vi ON ce.itemid = vi.itemid
  JOIN icu_stays_with_arf s ON ce.stay_id = s.stay_id
  WHERE ce.charttime >= s.intime 
    AND ce.charttime < DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
abnormal_vitals AS (
  SELECT stay_id,
    SUM(CASE 
          WHEN label = 'heart rate' AND (valuenum < 50 OR valuenum > 100) THEN 1
          WHEN label = 'mean blood pressure' AND (valuenum < 65 OR valuenum > 105) THEN 1
          WHEN label = 'respiratory rate' AND (valuenum < 10 OR valuenum > 25) THEN 1
          WHEN label = 'spo2' AND valuenum < 90 THEN 1
          ELSE 0
        END) AS abnormal_count
  FROM vitals_first_48h
  GROUP BY stay_id
),
instability_stats AS (
  SELECT 
    APPROX_QUANTILES(abnormal_count, 100)[OFFSET(95)] AS p95_instability_index
  FROM abnormal_vitals
),
cohort_instability AS (
  SELECT av.stay_id,
         av.abnormal_count,
         s.icu_los,
         s.hospital_expire_flag,
         NTILE(4) OVER (ORDER BY av.abnormal_count DESC) AS instability_quartile
  FROM abnormal_vitals av
  JOIN icu_stays_with_arf s ON av.stay_id = s.stay_id
),
top_quartile AS (
  SELECT stay_id, icu_los, hospital_expire_flag
  FROM cohort_instability
  WHERE instability_quartile = 1
),
general_icu_population AS (
  SELECT stay_id, 
         los AS icu_los, 
         hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays s
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON s.hadm_id = a.hadm_id
),
-- Count MAP < 65 and tachycardia (HR > 100) events for top quartile
vital_events_top AS (
  SELECT 
    t.stay_id,
    SUM(CASE WHEN di.label = 'mean blood pressure' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_less_65_count,
    SUM(CASE WHEN di.label = 'heart rate' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count
  FROM top_quartile t
  JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce ON t.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
  WHERE LOWER(di.label) IN ('mean blood pressure', 'heart rate')
    AND ce.valuenum IS NOT NULL
  GROUP BY t.stay_id
),
-- Count same events for general ICU population
vital_events_general AS (
  SELECT 
    g.stay_id,
    SUM(CASE WHEN di.label = 'mean blood pressure' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_less_65_count,
    SUM(CASE WHEN di.label = 'heart rate' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count
  FROM general_icu_population g
  JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce ON g.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
  WHERE LOWER(di.label) IN ('mean blood pressure', 'heart rate')
    AND ce.valuenum IS NOT NULL
  GROUP BY g.stay_id
),
-- Aggregate outcomes for top quartile
outcomes_top AS (
  SELECT
    AVG(map_less_65_count) AS avg_map_less_65,
    AVG(tachycardia_count) AS avg_tachycardia,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS median_icu_los,
    AVG(CAST(hospital_expire_flag = 1 AS FLOAT64)) AS mortality_rate
  FROM top_quartile t
  LEFT JOIN vital_events_top v ON t.stay_id = v.stay_id
),
-- Aggregate outcomes for general ICU population
outcomes_general AS (
  SELECT
    AVG(map_less_65_count) AS avg_map_less_65,
    AVG(tachycardia_count) AS avg_tachycardia,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS median_icu_los,
    AVG(CAST(hospital_expire_flag = 1 AS FLOAT64)) AS mortality_rate
  FROM general_icu_population g
  LEFT JOIN vital_events_general v ON g.stay_id = v.stay_id
)
-- Final comparison
SELECT;