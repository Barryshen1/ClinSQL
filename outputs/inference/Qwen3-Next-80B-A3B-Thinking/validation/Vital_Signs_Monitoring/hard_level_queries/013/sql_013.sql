WITH multi_trauma AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%trauma%' OR di.long_title LIKE '%injury%'
),

first_icu_stay AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime, 
    i.outtime, 
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),

filtered_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,  -- Added missing hadm_id
    p.gender,
    a.admittime,
    a.hospital_expire_flag,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM multi_trauma)
),

first_icu_filtered AS (
  SELECT 
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    fis.intime,
    fis.outtime,
    fis.los,
    fp.gender,
    fp.admission_age,
    fp.hospital_expire_flag
  FROM first_icu_stay fis
  JOIN filtered_patients fp
    ON fis.subject_id = fp.subject_id AND fis.hadm_id = fp.hadm_id
  WHERE fis.rn = 1
),

vital_signs AS (
  SELECT 
    c.stay_id,
    SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN c.itemid IN (220050, 220179) AND c.valuenum < 90 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN first_icu_filtered fis ON c.stay_id = fis.stay_id
  WHERE c.charttime BETWEEN fis.intime AND fis.intime + INTERVAL '24' HOUR
  GROUP BY c.stay_id
),

combined AS (
  SELECT 
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    fis.los,
    fis.hospital_expire_flag,
    COALESCE(vs.tachycardia_count, 0) AS tachycardia_count,
    COALESCE(vs.hypotension_count, 0) AS hypotension_count,
    COALESCE(vs.tachypnea_count, 0) AS tachypnea_count,
    (COALESCE(vs.tachycardia_count, 0) + COALESCE(vs.hypotension_count, 0) + COALESCE(vs.tachypnea_count, 0)) AS instability_score
  FROM first_icu_filtered fis
  LEFT JOIN vital_signs vs ON fis.stay_id = vs.stay_id
  WHERE fis.gender = 'M' AND fis.admission_age BETWEEN 68 AND 78
),

quartile_results AS (
  SELECT 
    quartile,
    COUNT(*) AS count,
    AVG(instability_score) AS mean_score,
    AVG(los) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM (
    SELECT 
      *,
      NTILE(4) OVER (ORDER BY instability_score) AS quartile
    FROM combined
  )
  GROUP BY quartile
),

top_decile_results AS (
  SELECT 
    AVG(tachycardia_count) AS mean_tachycardia,
    AVG(hypotension_count) AS mean_hypotension,
    AVG(tachypnea_count) AS mean_tachypnea
  FROM (
    SELECT 
      *,
      PERCENTILE_CONT(0.9) OVER (ORDER BY instability_score) AS top_decile_threshold
    FROM combined
  )
  WHERE instability_score >= top_decile_threshold
)

SELECT 
  CAST(quartile AS STRING) AS quartile,
  count,
  mean_score,
  mean_los,
  mortality_rate,
  NULL AS mean_tachycardia,
  NULL AS mean_hypotension,
  NULL AS mean_tachypnea
FROM quartile_results

UNION ALL

SELECT 
  'Top Decile' AS quartile,
  NULL AS count,
  NULL AS mean_score,
  NULL AS mean_los,
  NULL AS mortality_rate,
  mean_tachycardia,
  mean_hypotension,
  mean_tachypnea
FROM top_decile_results;