WITH filtered_patients AS (
  -- Filter male patients aged 78-88
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 78 AND 88
),
hhs_admissions AS (
  -- Identify admissions with primary HHS diagnosis (ICD-10)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE CAST(di.seq_num AS STRING) = '1' 
    AND di.icd_version = 'ICD-10'
    AND (di.icd_code LIKE 'E11.0%' 
         OR di.icd_code LIKE 'E13.0%' 
         OR di.icd_code LIKE 'E10.0%'
         OR di.icd_code = 'E87.0')
),
filtered_stays AS (
  -- Join to get qualifying ICU stays
  SELECT 
    fp.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM filtered_patients fp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON fp.subject_id = i.subject_id
  INNER JOIN hhs_admissions ha 
    ON i.subject_id = ha.subject_id AND i.hadm_id = ha.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
),
vitals_data AS (
  -- Extract HR, MAP, RR from chartevents
  SELECT 
    fs.stay_id,
    fs.intime,
    c.charttime,
    c.itemid,
    c.valuenum,
    -- Bin into 24-hour periods relative to intime
    TIMESTAMP_DIFF(c.charttime, fs.intime, HOUR) / 24 AS day_bin
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON fs.stay_id = c.stay_id
  WHERE c.itemid IN (211, 220045,  -- HR
                     52, 443,       -- MAP
                     618, 220210)   -- RR
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
),
cv_per_bin AS (
  -- Compute CV per vital per 24h bin
  SELECT 
    stay_id,
    day_bin,
    itemid,
    STDDEV(valuenum) / AVG(valuenum) AS cv
  FROM vitals_data
  GROUP BY stay_id, day_bin, itemid
  HAVING COUNT(valuenum) >= 2  -- Need at least 2 points for STDDEV
),
cv_sum_per_bin AS (
  -- Sum CVs for 3 vitals per bin (HR + MAP + RR)
  SELECT 
    stay_id,
    day_bin,
    COALESCE(SUM(CASE WHEN itemid IN (211, 220045) THEN cv END), 0) +
    COALESCE(SUM(CASE WHEN itemid IN (52, 443) THEN cv END), 0) +
    COALESCE(SUM(CASE WHEN itemid IN (618, 220210) THEN cv END), 0) AS cv_sum_bin
  FROM cv_per_bin
  GROUP BY stay_id, day_bin
),
stay_cv_sum AS (
  -- Average CV sum across bins per stay
  SELECT 
    stay_id,
    AVG(cv_sum_bin) AS instability_score,
    COUNT(day_bin) AS num_bins
  FROM cv_sum_per_bin
  GROUP BY stay_id
),
top_quartile_stays AS (
  -- Identify top quartile by instability_score
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score DESC) AS pct_rank
  FROM stay_cv_sum
  WHERE num_bins > 0  -- Only stays with data
  QUALIFY pct_rank <= 0.75  -- Top quartile (highest 25%)
),
abnormal_vitals AS (
  -- Compute abnormal vital counts (hours with >=1 abnormal)
  SELECT 
    fs.stay_id,
    -- Bin by hour for abnormality count
    TIMESTAMP_TRUNC(c.charttime, HOUR) AS hour_bin,
    CASE 
      WHEN c.itemid IN (211, 220045) AND (c.valuenum < 50 OR c.valuenum > 120) THEN 1
      WHEN c.itemid IN (52, 443) AND (c.valuenum < 65 OR c.valuenum > 110) THEN 1
      WHEN c.itemid IN (618, 220210) AND (c.valuenum < 12 OR c.valuenum > 30) THEN 1
      ELSE 0 
    END AS is_abnormal
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON fs.stay_id = c.stay_id
  WHERE c.itemid IN (211, 220045, 52, 443, 618, 220210)
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
),
abnormal_count_per_stay AS (
  SELECT 
    stay_id,
    COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN hour_bin END) AS abnormal_vital_count
  FROM abnormal_vitals
  GROUP BY stay_id
)
-- Final output for top quartile stays
SELECT 
  tqs.stay_id,
  tqs.instability_score AS stay_instability_score,
  NTILE(10) OVER (ORDER BY tqs.instability_score DESC) AS decile,
  COALESCE(ac.abnormal_vital_count, 0) AS abnormal_vital_count,
  fs.los AS icu_los,
  fs.hospital_expire_flag AS in_hospital_mortality
FROM top_quartile_stays tqs
INNER JOIN filtered_stays fs 
  ON tqs.stay_id = fs.stay_id
LEFT JOIN abnormal_count_per_stay ac 
  ON tqs.stay_id = ac.stay_id
ORDER BY tqs.instability_score DESC;