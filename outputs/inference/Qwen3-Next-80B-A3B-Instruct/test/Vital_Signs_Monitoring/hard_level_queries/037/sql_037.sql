WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(d_diag.long_title) LIKE '%heart failure%'
),

icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.hadm_id, i.intime, i.outtime, i.los,
         a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN cohort c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id
),

vitals_72h AS (
  SELECT 
    i.stay_id,
    SUM(CASE WHEN d.label = 'Heart Rate' AND c.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN d.label = 'Mean Arterial Pressure' AND c.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN d.label = 'Respiratory Rate' AND c.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_count
  FROM icu_stays i
  JOIN physionet-data.mimiciv_3_1_icu.chartevents c ON i.stay_id = c.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items d ON c.itemid = d.itemid
  WHERE c.charttime >= i.intime 
    AND c.charttime < i.intime + INTERVAL 72 HOUR
  GROUP BY i.stay_id
),

composite_score AS (
  SELECT 
    i.stay_id,
    i.los,
    i.hospital_expire_flag,
    COALESCE(v.tachycardia_count, 0) + COALESCE(v.map_low_count, 0) + COALESCE(v.tachypnea_count, 0) AS composite_instability_score,
    v.tachycardia_count,
    v.map_low_count,
    v.tachypnea_count
  FROM icu_stays i
  LEFT JOIN vitals_72h v ON i.stay_id = v.stay_id
),

quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY composite_instability_score) AS quartile
  FROM composite_score
)

SELECT
  PERCENTILE_CONT(composite_instability_score, 0.99) OVER () AS p99_composite_score,
  AVG(CASE WHEN quartile = 4 THEN tachycardia_count END) AS avg_tachycardia_top_quartile,
  AVG(CASE WHEN quartile = 4 THEN map_low_count END) AS avg_map_low_top_quartile,
  AVG(CASE WHEN quartile = 4 THEN tachypnea_count END) AS avg_tachypnea_top_quartile,
  AVG(CASE WHEN quartile = 4 THEN los END) AS avg_los_top_quartile,
  AVG(CASE WHEN quartile = 4 THEN CAST(hospital_expire_flag AS FLOAT64) END) AS avg_mortality_top_quartile,
  AVG(tachycardia_count) AS avg_tachycardia_all,
  AVG(map_low_count) AS avg_map_low_all,
  AVG(tachypnea_count) AS avg_tachypnea_all,
  AVG(los) AS avg_los_all,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS avg_mortality_all
FROM quartiles;