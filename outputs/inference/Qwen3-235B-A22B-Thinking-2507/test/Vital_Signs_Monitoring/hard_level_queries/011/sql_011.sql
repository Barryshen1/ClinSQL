WITH instability_scores AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.stay_id = i.stay_id
  WHERE 
    c.valuenum IS NOT NULL
    AND d.lownormalvalue IS NOT NULL
    AND d.highnormalvalue IS NOT NULL
    AND (c.valuenum < d.lownormalvalue OR c.valuenum > d.highnormalvalue)
    AND c.charttime >= i.intime
    AND c.charttime <= i.intime + INTERVAL '1' DAY
  GROUP BY c.stay_id
),
cohort AS (
  SELECT 
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    COALESCE(s.instability_score, 0) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN instability_scores s
    ON i.stay_id = s.stay_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 55 AND 65
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        d.hadm_id = i.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
),
percentile_calc AS (
  SELECT 
    (COUNTIF(instability_score <= 60) * 100.0 / COUNT(*)) AS percentile
  FROM cohort
),
top_decile AS (
  SELECT
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM (
    SELECT 
      *,
      NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
    FROM cohort
  )
  WHERE decile = 1
)
SELECT
  p.percentile,
  t.avg_icu_los,
  t.mortality_rate
FROM percentile_calc p
CROSS JOIN top_decile t;