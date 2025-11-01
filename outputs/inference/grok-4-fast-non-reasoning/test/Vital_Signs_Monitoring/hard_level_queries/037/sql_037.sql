WITH cohort AS (
  -- Male 45-55 yo with primary HF admission and ICU stay (first per patient)
  SELECT DISTINCT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1 AND d.icd_code LIKE 'I50%'
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id AND i.los > 0
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.admittime <= i.intime  -- Ensure admission before ICU
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.stay_id) = 1
),

vital_windows AS (
  -- First 72h vitals, binned into 6h intervals
  SELECT
    c.subject_id,
    c.stay_id,
    c.intime,
    FLOOR(DATETIME_DIFF(ce.charttime, c.intime, HOUR) / 6) AS bin_id,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia,
    MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS has_hypotension,
    MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS has_tachypnea
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 220052, 220210)  -- HR, MAP, RR
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.stay_id, c.intime, bin_id
  HAVING bin_id <= 11  -- 12 bins: 0-11
),

instability_scores AS (
  -- Composite score: sum unstable bins (any abnormality)
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    COUNT(DISTINCT vw.bin_id) AS num_bins,
    SUM(CASE 
      WHEN vw.has_tachycardia = 1 OR vw.has_hypotension = 1 OR vw.has_tachypnea = 1 
      THEN 1 ELSE 0 
    END) AS unstable_bins,
    -- Score: unstable / total bins (0-1 scale, normalized to 0-12)
    SUM(CASE 
      WHEN vw.has_tachycardia = 1 OR vw.has_hypotension = 1 OR vw.has_tachypnea = 1 
      THEN 1 ELSE 0 
    END) * 12.0 / GREATEST(COUNT(DISTINCT vw.bin_id), 1) AS score
  FROM cohort c
  LEFT JOIN vital_windows vw
    ON c.stay_id = vw.stay_id
  GROUP BY c.stay_id, c.los, c.hospital_expire_flag
),

quartiles AS (
  -- Add quartiles by score
  SELECT
    *,
    NTILE(4) OVER (ORDER BY score DESC) AS quartile  -- 1=least unstable, 4=most
  FROM instability_scores
),

-- Pre-compute vital flags for HF cohort (for Q4)
hf_vital_flags AS (
  SELECT
    c.stay_id,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS any_tachycardia,
    MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS any_hypotension,
    MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS any_tachypnea
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 220052, 220210)
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
),

-- Overall ICU population (male 45-55, no HF filter)
overall_icu AS (
  SELECT
    i.stay_id,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND i.los > 0
),

-- Pre-compute vital flags for overall ICU
overall_vital_flags AS (
  SELECT
    o.stay_id,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS any_tachycardia,
    MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS any_hypotension,
    MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS any_tachypnea
  FROM overall_icu o
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON o.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 220052, 220210)
    AND ce.charttime >= (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` ic WHERE ic.stay_id = o.stay_id)
    AND ce.charttime <= (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` ic WHERE ic.stay_id = o.stay_id) + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY o.stay_id
),

overall_outcomes AS (
  SELECT
    'Overall ICU' AS group_type,
    AVG(CASE WHEN ovf.any_tachycardia = 1 THEN 1.0 ELSE 0 END) * 100 AS avg_tachycardia_pct,
    AVG(CASE WHEN ovf.any_hypotension = 1 THEN 1.0 ELSE 0 END) * 100 AS avg_hypotension_pct,
    AVG(CASE WHEN ovf.any_tachypnea = 1 THEN 1.0 ELSE 0 END) * 100 AS avg_tachypnea_pct,
    AVG(oi.los) AS avg_los_days,
    AVG(CASE WHEN oi.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100 AS mortality_pct
  FROM overall_icu oi
  LEFT JOIN overall_vital_flags ovf ON oi.stay_id = ovf.stay_id
),

q4_outcomes AS (
  SELECT
    'Q4 (Most Unstable)' AS group_type,
    AVG(CASE WHEN q.quartile = 4 AND hvf.any_tachycardia = 1 THEN 1.0 ELSE 0 END) * 100 AS avg_tachycardia_pct,
    AVG(CASE WHEN q.quartile = 4 AND hvf.any_hypotension = 1 THEN 1.0 ELSE 0 END) * 100 AS avg_hypotension_pct,
    AVG(CASE WHEN q.quartile = 4 AND hvf.any_tachypnea = 1 THEN 1.0 ELSE 0 END) * 100 AS avg_tachypnea_pct,
    AVG(CASE WHEN q.quartile = 4 THEN q.los ELSE NULL END) AS avg_los_days,
    AVG(CASE WHEN q.quartile = 4 AND q.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100 AS mortality_pct
  FROM quartiles q
  LEFT JOIN hf_vital_flags hvf ON q.stay_id = hvf.stay_id
  GROUP BY 1  -- Single row output
)

-- 99th percentile of score
SELECT
  '99th Percentile Instability Score' AS metric,
  PERCENTILE_CONT(score, 0.99) OVER () AS value
FROM instability_scores

UNION ALL

-- Comparisons
SELECT group_type, avg_tachycardia_pct, avg_hypotension_pct, avg_tachypnea_pct, avg_los_days, mortality_pct
FROM q4_outcomes
UNION ALL
SELECT group_type, avg_tachycardia_pct, avg_hypotension_pct, avg_tachypnea_pct, avg_los_days, mortality_pct
FROM overall_outcomes;