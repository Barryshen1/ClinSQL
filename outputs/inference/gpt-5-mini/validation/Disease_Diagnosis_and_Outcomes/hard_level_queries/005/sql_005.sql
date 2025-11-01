WITH
-- female inpatient admissions (anchor_age used for age)
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.hadm_id IS NOT NULL
),

-- diagnoses joined to descriptive titles
diagnoses_with_title AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    COALESCE(LOWER(dd.long_title), '') AS long_title_lower
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
),

-- admissions that have at least one heart-failure diagnosis (by title)
heart_failure_hadm AS (
  SELECT DISTINCT hadm_id
  FROM diagnoses_with_title
  WHERE long_title_lower LIKE '%heart failure%'
),

-- compute per-admission "risk_score" proxy and major complication flag
-- risk_score = count distinct icd_codes on the admission excluding HF codes
-- major_complication = 1 if any diagnosis title matches a set of serious-complication keywords
risk_and_complication_by_hadm AS (
  SELECT
    hadm_id,
    COALESCE(COUNT(DISTINCT CASE WHEN long_title_lower NOT LIKE '%heart failure%' THEN icd_code END), 0) AS risk_score,
    MAX(CASE
          WHEN long_title_lower LIKE '%acute kidney%' THEN 1
          WHEN long_title_lower LIKE '%acute renal%' THEN 1
          WHEN long_title_lower LIKE '%acute respiratory%' THEN 1
          WHEN long_title_lower LIKE '%respiratory failure%' THEN 1
          WHEN long_title_lower LIKE '%sepsis%' THEN 1
          WHEN long_title_lower LIKE '%myocardial infarction%' THEN 1
          WHEN long_title_lower LIKE '%infarction%' THEN 1
          WHEN long_title_lower LIKE '%stroke%' THEN 1
          WHEN long_title_lower LIKE '%cardiac arrest%' THEN 1
          ELSE 0 END) AS major_complication_flag
  FROM diagnoses_with_title
  GROUP BY hadm_id
),

-- admissions that had any ICU stay
icu_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- final cohort: female admissions age 43-53 that have HF diagnosis and ICU stay
cohort_admissions AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    fa.dod,
    COALESCE(rc.risk_score, 0) AS risk_score,
    COALESCE(rc.major_complication_flag, 0) AS major_complication_flag
  FROM female_admissions fa
  JOIN heart_failure_hadm hf
    ON fa.hadm_id = hf.hadm_id
  JOIN icu_hadm iu
    ON fa.hadm_id = iu.hadm_id
  LEFT JOIN risk_and_complication_by_hadm rc
    ON fa.hadm_id = rc.hadm_id
),

-- compute cohort quantiles (approx) for risk_score (25th, 50th, 75th)
cohort_quantiles AS (
  SELECT
    APPROX_QUANTILES(risk_score, 4) AS q_array,  -- returns 5 values: 0%,25%,50%,75%,100%
    COUNT(*) AS cohort_n
  FROM cohort_admissions
),

-- cohort-level summarized stats
cohort_metrics AS (
  SELECT
    cq.cohort_n,
    cq.q_array[OFFSET(1)] AS risk_q25,
    cq.q_array[OFFSET(2)] AS risk_median,
    cq.q_array[OFFSET(3)] AS risk_q75,
    SUM(CASE WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30 THEN 1 ELSE 0 END) AS deaths_30d,
    SUM(CASE WHEN major_complication_flag = 1 THEN 1 ELSE 0 END) AS major_complications,
    AVG(CASE
          WHEN NOT (dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30)
          THEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY)
          ELSE NULL END) AS avg_los_survivors_days
  FROM cohort_quantiles cq
  CROSS JOIN cohort_admissions ca
  GROUP BY cq.q_array, cq.cohort_n
),

-- risk scores for all female admissions age 43-53 (to compute percentile)
all_female_risk_scores AS (
  SELECT
    fa.hadm_id,
    COALESCE(rc.risk_score, 0) AS risk_score
  FROM female_admissions fa
  LEFT JOIN risk_and_complication_by_hadm rc
    ON fa.hadm_id = rc.hadm_id
)

-- Final select: compute metrics and percentile of cohort median among all female 43-53.
SELECT
  cm.cohort_n AS cohort_size,
  cm.risk_median AS cohort_risk_median,
  cm.risk_q25 AS cohort_risk_q25,
  cm.risk_q75 AS cohort_risk_q75,
  -- 30-day mortality rate (%)
  SAFE_DIVIDE(cm.deaths_30d, cm.cohort_n) * 100.0 AS mortality_30d_percent,
  -- major complication rate (%)
  SAFE_DIVIDE(cm.major_complications, cm.cohort_n) * 100.0 AS major_complication_percent,
  cm.avg_los_survivors_days AS avg_los_days_among_survivors,
  -- percentile of the cohort median risk among all female 43-53 admissions:
  -- fraction of all female admissions with risk_score <= cohort median * 100
  (
    SELECT
      SAFE_DIVIDE(COUNTIF(risk_score <= cm.risk_median), COUNT(*)) * 100.0
    FROM all_female_risk_scores
  ) AS cohort_median_risk_percentile_vs_all_female_43_53
FROM cohort_metrics cm
LIMIT 1;