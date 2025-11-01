WITH cohort AS (
  -- Specific cohort: males 82-92 with acute respiratory failure (primary dx)
  SELECT 
    i.stay_id, i.subject_id, i.hadm_id, i.intime, i.outtime, i.los,
    p.gender, p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND d.icd_version = 'ICD-10-CM'  -- Correct version string
    AND d.icd_code LIKE 'J96.%'  -- Acute respiratory failure variants
    AND d.seq_num = 1  -- Primary diagnosis
),

general_icu AS (
  -- General ICU: all adult stays (for fair comparison)
  SELECT 
    i.stay_id, i.subject_id, i.hadm_id, i.intime, i.outtime, i.los,
    p.gender, p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.anchor_age >= 18  -- Adult only
),

vitals AS (
  -- Vital events in first 72h (MAP and HR; filter later)
  SELECT 
    c.stay_id, c.intime,
    ce.charttime, ce.itemid, ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (220045, 220277)  -- HR=220045, MAP=220277

  UNION ALL

  SELECT 
    g.stay_id, g.intime,
    ce.charttime, ce.itemid, ce.valuenum
  FROM general_icu g
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON g.stay_id = ce.stay_id
  WHERE ce.charttime >= g.intime
    AND ce.charttime <= g.intime + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (220045, 220277)
),

vitals_map AS (
  SELECT 
    stay_id, intime, charttime, valuenum
  FROM vitals
  WHERE itemid = 220277  -- MAP
),

vitals_hr AS (
  SELECT 
    stay_id, intime, charttime, valuenum
  FROM vitals
  WHERE itemid = 220045  -- HR
),

map_burdens AS (
  -- MAP burden: proportion of time <65 (using minute diffs for precision)
  SELECT 
    v.stay_id,
    SAFE_DIVIDE(
      SUM(
        CASE 
          WHEN v.valuenum < 65 THEN 
            TIMESTAMP_DIFF(
              COALESCE(LEAD(v.charttime) OVER (PARTITION BY v.stay_id ORDER BY v.charttime), v.intime + INTERVAL 72 HOUR), 
              v.charttime, 
              MINUTE
            ) / 60.0
          ELSE 0 
        END
      ),
      72.0
    ) AS map_burden
  FROM vitals_map v
  GROUP BY v.stay_id
  HAVING COUNT(*) > 0
),

hr_burdens AS (
  -- HR burden: proportion of time >100
  SELECT 
    v.stay_id,
    SAFE_DIVIDE(
      SUM(
        CASE 
          WHEN v.valuenum > 100 THEN 
            TIMESTAMP_DIFF(
              COALESCE(LEAD(v.charttime) OVER (PARTITION BY v.stay_id ORDER BY v.charttime), v.intime + INTERVAL 72 HOUR), 
              v.charttime, 
              MINUTE
            ) / 60.0
          ELSE 0 
        END
      ),
      72.0
    ) AS hr_burden
  FROM vitals_hr v
  GROUP BY v.stay_id
  HAVING COUNT(*) > 0
),

burdens_cohort AS (
  SELECT 
    c.stay_id,
    COALESCE(mb.map_burden, 0) + COALESCE(hb.hr_burden, 0) AS composite_score,
    COALESCE(mb.map_burden, 0) AS map_burden,
    COALESCE(hb.hr_burden, 0) AS hr_burden,
    c.los,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN map_burdens mb ON c.stay_id = mb.stay_id
  LEFT JOIN hr_burdens hb ON c.stay_id = hb.stay_id
  WHERE mb.stay_id IS NOT NULL OR hb.stay_id IS NOT NULL  -- At least one burden available
),

burdens_general AS (
  SELECT 
    g.stay_id,
    COALESCE(mb.map_burden, 0) + COALESCE(hb.hr_burden, 0) AS composite_score,
    COALESCE(mb.map_burden, 0) AS map_burden,
    COALESCE(hb.hr_burden, 0) AS hr_burden,
    g.los,
    g.hospital_expire_flag
  FROM general_icu g
  LEFT JOIN map_burdens mb ON g.stay_id = mb.stay_id
  LEFT JOIN hr_burdens hb ON g.stay_id = hb.stay_id
  WHERE mb.stay_id IS NOT NULL OR hb.stay_id IS NOT NULL
),

summary_cohort AS (
  SELECT 
    'Cohort (Males 82-92, Acute Resp Failure)' AS group_type,
    PERCENTILE_CONT(0.25) OVER () AS p25_composite,
    PERCENTILE_CONT(0.50) OVER () AS median_composite,
    PERCENTILE_CONT(0.75) OVER () AS p75_composite,
    (PERCENTILE_CONT(0.75) OVER () - PERCENTILE_CONT(0.25) OVER ()) AS iqr_composite,
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS avg_mortality
  FROM burdens_cohort
),

summary_general AS (
  SELECT 
    'General ICU' AS group_type,
    PERCENTILE_CONT(0.25) OVER () AS p25_composite,
    PERCENTILE_CONT(0.50) OVER () AS median_composite,
    PERCENTILE_CONT(0.75) OVER () AS p75_composite,
    (PERCENTILE_CONT(0.75) OVER () - PERCENTILE_CONT(0.25) OVER ()) AS iqr_composite,
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS avg_mortality
  FROM burdens_general
)

-- Final comparison
SELECT * FROM summary_cohort
UNION ALL
SELECT * FROM summary_general;