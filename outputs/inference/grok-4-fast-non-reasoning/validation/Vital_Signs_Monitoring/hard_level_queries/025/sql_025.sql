WITH cohort AS (
  -- Define cohort: male, 55-65, ICU, post-cardiac arrest (first ICU stay)
  SELECT 
    DISTINCT icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = icu.subject_id 
        AND diag.hadm_id = CAST(icu.hadm_id AS STRING)
        AND (
          (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '427.5%') OR
          (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I46%')
        )
    )
    AND icu.stay_id = (
      SELECT MIN(stay.stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` stay
      WHERE stay.subject_id = icu.subject_id
    )
),

vitals AS (
  -- Extract first 24h vitals for cohort (first stay)
  SELECT 
    c.subject_id,
    c.stay_id,
    c.intime,
    ce.itemid,
    ce.valuenum,
    ce.charttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 1 DAY
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (220045, 220210, 220179, 220180, 223761, 678)  -- HR, RR, SBP, DBP, Temp (C)
),

per_item_stats AS (
  -- Compute per-item stats: mean, std, CV, extreme flag
  SELECT 
    subject_id,
    itemid,
    AVG(valuenum) AS mean_val,
    STDDEV(valuenum) AS std_val,
    CASE 
      WHEN AVG(valuenum) > 0 THEN STDDEV(valuenum) / AVG(valuenum) 
      ELSE 0 
    END AS cv,
    COUNT(CASE 
      WHEN (itemid = 220045 AND (valuenum > 140 OR valuenum < 50)) OR  -- HR extremes
           (itemid = 220210 AND (valuenum > 35 OR valuenum < 8)) OR   -- RR
           (itemid = 220179 AND (valuenum < 90 OR valuenum > 180)) OR -- SBP
           (itemid = 220180 AND (valuenum < 50 OR valuenum > 100)) OR -- DBP
           (itemid IN (223761, 678) AND (valuenum > 39 OR valuenum < 35))  -- Temp
      THEN 1 
    END) AS num_extremes,
    COUNT(*) AS total_measurements
  FROM vitals
  GROUP BY subject_id, itemid
),

instability_score AS (
  -- Compute per-patient instability score: avg CV + proportion extremes, scaled to 0-100
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.los,
    c.hospital_expire_flag,
    GREATEST(0, LEAST(100, 
      COALESCE(
        AVG(pis.cv) * 50 +  -- Average CV across vitals (scaled 0-50)
        (SUM(pis.num_extremes) * 1.0 / NULLIF(SUM(pis.total_measurements), 0)) * 50,  -- Normalized extreme proportion (scaled 0-50)
        0
      )
    )) AS instability_score
  FROM cohort c
  LEFT JOIN per_item_stats pis
    ON c.subject_id = pis.subject_id
  GROUP BY c.subject_id, c.hadm_id, c.los, c.hospital_expire_flag
),

percentile_70 AS (
  -- Global percentile for score <= 70
  SELECT 
    COUNT(CASE WHEN instability_score <= 70 THEN 1 END) * 100.0 / COUNT(*) AS percentile_for_70
  FROM instability_score
),

top_decile AS (
  -- Identify top decile (most unstable) for LOS/mortality
  SELECT 
    subject_id,
    los,
    hospital_expire_flag
  FROM (
    SELECT 
      *,
      NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
    FROM instability_score
  )
  WHERE decile = 1
)

-- Main results
SELECT 
  -- Part 1: Percentile for score=70
  p70.percentile_for_70,
  
  -- Part 2: Mean LOS and mortality for most unstable decile (top 10%, decile=1)
  AVG(td.los) AS mean_los_most_unstable_decile,
  AVG(CAST(td.hospital_expire_flag AS FLOAT64)) AS mortality_most_unstable_decile

FROM percentile_70 p70
CROSS JOIN top_decile td;