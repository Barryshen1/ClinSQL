WITH dvt_admissions AS (
  -- Female patients age 59–69 with a DVT diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    COALESCE(
      CAST(a.deathtime AS TIMESTAMP),
      CAST(p.dod AS TIMESTAMP)
    ) AS death_datetime,
    p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dvt
      ON a.subject_id = dvt.subject_id
      AND a.hadm_id = dvt.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON dvt.icd_code = dd.icd_code
      AND dvt.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND dd.icd_code LIKE 'I82%'  -- DVT ICD-10
),
comorbidity_counts AS (
  -- Count distinct comorbid diagnoses per admission, excluding the DVT code
  SELECT
    da.subject_id,
    da.hadm_id,
    COUNT(DISTINCT diag.icd_code) AS comorbidity_count
  FROM
    dvt_admissions da
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON da.subject_id = diag.subject_id
      AND da.hadm_id = diag.hadm_id
  WHERE
    diag.icd_code NOT LIKE 'I82%'
  GROUP BY
    da.subject_id, da.hadm_id
),
percentiles AS (
  -- Compute the 75th percentile of comorbidity_count
  SELECT
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS comorbidity_75th
  FROM
    comorbidity_counts
),
high_comorbidity AS (
  -- Admissions above the 75th percentile
  SELECT
    cc.subject_id,
    cc.hadm_id,
    cc.comorbidity_count
  FROM
    comorbidity_counts cc
    CROSS JOIN percentiles p
  WHERE
    cc.comorbidity_count > p.comorbidity_75th
),
cohort AS (
  -- Merge back to get admission and death times
  SELECT
    hc.subject_id,
    hc.hadm_id,
    da.admittime,
    da.death_datetime,
    da.age_at_admission,
    hc.comorbidity_count,
    TIMESTAMP_DIFF(da.death_datetime, da.admittime, DAY) AS days_to_death,
    -- 30-day mortality flag
    CASE
      WHEN da.death_datetime IS NOT NULL
        AND TIMESTAMP_DIFF(da.death_datetime, da.admittime, DAY) <= 30
      THEN 1 ELSE 0
    END AS died_within_30d
  FROM
    high_comorbidity hc
    JOIN dvt_admissions da
      ON hc.subject_id = da.subject_id
      AND hc.hadm_id = da.hadm_id
),
complications AS (
  -- Flag admissions with a PE diagnosis (major complication)
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN dd.icd_code LIKE 'I26%' THEN 1 ELSE 0 END) AS has_pe
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON c.subject_id = diag.subject_id
      AND c.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON diag.icd_code = dd.icd_code
      AND diag.icd_version = dd.icd_version
  GROUP BY
    c.subject_id, c.hadm_id
),
cohort_with_comp AS (
  -- Combine cohort with complication flags and compute risk score
  SELECT
    c.*,
    COALESCE(comp.has_pe, 0) AS major_complication,
    -- composite risk = age_at_admission + comorbidity_count
    c.age_at_admission + c.comorbidity_count AS risk_score
  FROM
    cohort c
    LEFT JOIN complications comp
      ON c.subject_id = comp.subject_id
      AND c.hadm_id = comp.hadm_id
),
risk_quartiles AS (
  SELECT
    APPROX_QUANTILES(risk_score, 4) AS quartiles
  FROM
    cohort_with_comp
),
summary AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS cohort_size,
    100.0 * SUM(died_within_30d) / COUNT(*) AS pct_30d_mortality,
    100.0 * SUM(major_complication) / COUNT(*) AS pct_major_complication,
    -- median survival among decedents
    APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)] AS median_days_to_death,
    -- report risk score quartiles
    rq.quartiles[OFFSET(0)] AS risk_q1,
    rq.quartiles[OFFSET(1)] AS risk_q2,
    rq.quartiles[OFFSET(2)] AS risk_q3,
    rq.quartiles[OFFSET(3)] AS risk_q4
  FROM
    cohort_with_comp
    CROSS JOIN risk_quartiles rq
)
SELECT * FROM summary;