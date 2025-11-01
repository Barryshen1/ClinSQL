WITH
-- 1. Base cohort: female ICU patients age 49-59 with an ACS diagnosis
acs_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
    AND icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.subject_id = icu.subject_id
        AND d.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
    )
),

-- 2. Compute first-24h composite vital instability scores from chartevents
first24_scores AS (
  SELECT
    s.subject_id,
    s.stay_id,
    -- composite score: HR + MAP + RR + SpO2 abnormalities
    (CASE WHEN MAX(CASE WHEN LOWER(d.label) LIKE '%heart rate%' THEN ce.valuenum END) > 100 THEN 1 ELSE 0 END)
    + (CASE WHEN MIN(CASE WHEN LOWER(d.label) LIKE '%arterial pressure%' THEN ce.valuenum END) < 65 THEN 1 ELSE 0 END)
    + (CASE WHEN MAX(CASE WHEN LOWER(d.label) LIKE '%respiratory rate%' THEN ce.valuenum END) > 20 THEN 1 ELSE 0 END)
    + (CASE WHEN MIN(CASE WHEN LOWER(d.label) LIKE '%oxygen saturation%' THEN ce.valuenum END) < 90 THEN 1 ELSE 0 END)
    AS score
  FROM
    acs_icustays s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.subject_id = ce.subject_id
    AND s.hadm_id    = ce.hadm_id
    AND s.stay_id    = ce.stay_id
    AND ce.charttime BETWEEN s.intime
                        AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    s.subject_id,
    s.stay_id
),

-- 3. Combine cohort with scores
cohort_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    s.score
  FROM acs_icustays c
  JOIN first24_scores s
    ON c.subject_id = s.subject_id
    AND c.stay_id    = s.stay_id
),

-- 4. Compute counts for percentile
percentile_calc AS (
  SELECT
    COUNT(*) AS total_n,
    SUM(CASE WHEN score <= 70 THEN 1 ELSE 0 END) AS le_70_n
  FROM cohort_scores
),

-- 5. Compute 90th percentile cutoff
p90 AS (
  SELECT
    APPROX_QUANTILES(score, 100)[OFFSET(90)] AS score_p90
  FROM cohort_scores
),

-- 6. Top decile cohort
top_decile AS (
  SELECT
    cs.*
  FROM
    cohort_scores cs
  CROSS JOIN
    p90
  WHERE
    cs.score >= p90.score_p90
),

-- 7. Add hospital mortality flag
top_decile_with_mort AS (
  SELECT
    td.*,
    adm.hospital_expire_flag
  FROM
    top_decile td
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON td.subject_id = adm.subject_id
    AND td.hadm_id    = adm.hadm_id
)

-- Final outputs
SELECT
  -- Percentile rank of a score of 70
  ROUND(100.0 * pc.le_70_n / pc.total_n, 2) AS percentile_of_70,
  -- Mean ICU LOS in days for the top decile
  ROUND(AVG(td.los), 2) AS mean_icu_los_days,
  -- Hospital mortality % among top decile
  ROUND(100.0 * SUM(td.hospital_expire_flag) / COUNT(*), 2) AS hospital_mortality_pct
FROM
  percentile_calc pc,
  top_decile_with_mort td;