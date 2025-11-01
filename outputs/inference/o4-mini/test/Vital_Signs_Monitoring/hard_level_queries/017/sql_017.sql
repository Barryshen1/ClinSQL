WITH
-- 1) Base ICU stays for female patients aged 83–93
base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_year,
    p.gender,
    -- approximate age at ICU admission
    EXTRACT(YEAR FROM icu.intime) - p.anchor_year AS age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
    AND icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM icu.intime) - p.anchor_year BETWEEN 83 AND 93
),

-- 2) Flag which stays have an asthma diagnosis
asthma_flag AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    TRUE AS has_asthma
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON d.icd_code = ddi.icd_code
    AND d.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%asthma%'
),

-- 3) Combine base with asthma flag (default FALSE for no asthma)
cohort AS (
  SELECT
    b.*,
    IFNULL(af.has_asthma, FALSE) AS has_asthma
  FROM base b
  LEFT JOIN asthma_flag af
    ON b.subject_id = af.subject_id
    AND b.hadm_id = af.hadm_id
),

-- 4) Identify the Instability Score itemid
instability_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'instability score'
  LIMIT 1
),

-- 5) All instability‐score measurements in first 72h
scores AS (
  SELECT
    c.stay_id,
    ce.valuenum AS score
  FROM cohort c
  JOIN instability_item ii
    ON TRUE
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = c.stay_id
    AND ce.itemid = ii.itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime
                        AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
),

-- 6) Per‐stay total “burden” = sum of all scores in 72h
per_stay_burden AS (
  SELECT
    s.stay_id,
    SUM(s.score) AS total_burden
  FROM scores s
  GROUP BY s.stay_id
),

-- 7) Asthma‐cohort SD & percentiles over *all* individual scores
asthma_stats AS (
  SELECT
    STDDEV_SAMP(score)                AS score_stddev,
    APPROX_QUANTILES(score, 100)[OFFSET(25)]  AS pct_25,
    APPROX_QUANTILES(score, 100)[OFFSET(50)]  AS pct_50,
    APPROX_QUANTILES(score, 100)[OFFSET(75)]  AS pct_75,
    APPROX_QUANTILES(score, 100)[OFFSET(95)]  AS pct_95
  FROM scores s
  JOIN cohort c
    ON s.stay_id = c.stay_id
  WHERE c.has_asthma
),

-- 8) Aggregate per‐cohort: avg burden, avg LOS, mortality rate
aggregate_stats AS (
  SELECT
    c.has_asthma,
    COUNT(*)                               AS n_stays,
    AVG(psb.total_burden)                  AS avg_score_burden,
    AVG(c.los)                             AS avg_icu_los,
    AVG(IF(c.hospital_expire_flag=1,1,0))  AS mortality_rate
  FROM cohort c
  LEFT JOIN per_stay_burden psb
    ON c.stay_id = psb.stay_id
  GROUP BY c.has_asthma
)

-- Final output: both the detailed asthma‐only distribution and the 2‐cohort comparison
SELECT
  'Asthma Cohort (female, age 83–93)' AS cohort_descr,
  a.score_stddev,
  a.pct_25,
  a.pct_50,
  a.pct_75,
  a.pct_95,
  NULL            AS avg_score_burden,
  NULL            AS avg_icu_los,
  NULL            AS mortality_rate
FROM asthma_stats a

UNION ALL

SELECT
  CASE WHEN ag.has_asthma THEN 'Asthma Cohort' ELSE 'Non-asthma Cohort' END,
  NULL, NULL, NULL, NULL, NULL,
  ag.avg_score_burden,
  ag.avg_icu_los,
  ag.mortality_rate
FROM aggregate_stats ag
ORDER BY cohort_descr;