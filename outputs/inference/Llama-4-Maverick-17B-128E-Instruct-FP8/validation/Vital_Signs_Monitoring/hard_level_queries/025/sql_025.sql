WITH 
-- Step 1: Filter patients based on age, gender, and condition (post-cardiac arrest)
patients_filtered AS (
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 55 AND 65
),

-- Step 2: Identify hospital admissions for these patients with cardiac arrest diagnosis
admissions_cardiac_arrest AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Cardiac arrest%' AND a.subject_id IN (SELECT subject_id FROM patients_filtered)
),

-- Step 3: Get ICU stay information for these admissions
icustays_filtered AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN admissions_cardiac_arrest a ON i.hadm_id = a.hadm_id
),

-- Step 4: Calculate vital sign instability score for the first 24 hours
vital_signs AS (
  SELECT i.stay_id, 
         -- Example: Standard deviation of heart rate as a measure of instability
         STDDEV(c.valuenum) AS hr_instability
  FROM icustays_filtered i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  AND d.label = 'Heart Rate'
  GROUP BY i.stay_id
),

-- Step 5: Calculate percentile of the vital-sign instability score
percentile_calc AS (
  SELECT 
    APPROX_QUANTILES(hr_instability, 100)[OFFSET(70)] AS percentile_70,
    APPROX_QUANTILES(hr_instability, 10)[OFFSET(9)] AS top_decile_threshold
  FROM vital_signs
),

-- Step 6: Calculate mean ICU LOS and mortality for the most unstable decile
top_decile_stats AS (
  SELECT 
    AVG(i.los) AS mean_icu_los,
    AVG(CASE WHEN a.dischtime = a.deathtime THEN 1 ELSE 0 END) AS mortality
  FROM icustays_filtered i
  JOIN vital_signs v ON i.stay_id = v.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN percentile_calc p ON 1=1
  WHERE v.hr_instability >= p.top_decile_threshold
)

-- Final output
SELECT 
  (SELECT percentile_70 FROM percentile_calc) AS percentile_70,
  (SELECT mean_icu_los FROM top_decile_stats) AS mean_icu_los,
  (SELECT mortality FROM top_decile_stats) AS mortality;