WITH
-- 1) Identify admissions with a DVT diagnosis using d_icd_diagnoses text matching
dvt_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON dx.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
      ON ddesc.icd_code = dx.icd_code
      AND COALESCE(CAST(ddesc.icd_version AS STRING), '') = COALESCE(CAST(dx.icd_version AS STRING), '')
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    -- text-based DVT identification: common strings in diagnosis descriptions
    AND (
      LOWER(ddesc.long_title) LIKE '%deep vein%'
      OR LOWER(ddesc.long_title) LIKE '%venous embol%'
      OR LOWER(ddesc.long_title) LIKE '%phleb%'
      OR LOWER(ddesc.long_title) LIKE '%venous thromb%'
      OR LOWER(ddesc.long_title) LIKE '%venous thrombo%'
    )
),

-- 2) Compute comorbidity counts per admission (exclude DVT diagnoses from the count)
comorbidity_counts AS (
  SELECT
    dx.hadm_id,
    COUNT(DISTINCT dx.icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
      ON ddesc.icd_code = dx.icd_code
      AND COALESCE(CAST(ddesc.icd_version AS STRING), '') = COALESCE(CAST(dx.icd_version AS STRING), '')
  WHERE
    dx.hadm_id IN (SELECT hadm_id FROM dvt_admissions)
    -- exclude the codes that describe DVT (so the primary DVT diagnosis doesn't inflate comorbidity_count)
    AND NOT (
      LOWER(ddesc.long_title) LIKE '%deep vein%'
      OR LOWER(ddesc.long_title) LIKE '%venous embol%'
      OR LOWER(ddesc.long_title) LIKE '%phleb%'
      OR LOWER(ddesc.long_title) LIKE '%venous thromb%'
      OR LOWER(ddesc.long_title) LIKE '%venous thrombo%'
    )
  GROUP BY dx.hadm_id
),

-- 3) Percentile 75 of comorbidity_count among the candidate cohort
comorb_75 AS (
  SELECT
    -- approximate 75th percentile (0..100 buckets -> offset 75)
    (APPROX_QUANTILES(comorbidity_count, 100))[OFFSET(75)] AS p75
  FROM comorbidity_counts
),

-- 4) Admissions that are above the 75th percentile (strictly greater per request)
high_comorb_cohort AS (
  SELECT
    da.*,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count
  FROM dvt_admissions da
  LEFT JOIN comorbidity_counts cc USING (hadm_id)
  CROSS JOIN comorb_75
  WHERE COALESCE(cc.comorbidity_count, 0) > COALESCE(comorb_75.p75, 0)
),

-- 5) Major complication flags per admission (presence of diagnosis matching major complication keywords)
hadm_complications AS (
  SELECT
    hc.hadm_id,
    MAX(CASE WHEN (
        LOWER(ddesc.long_title) LIKE '%sepsis%'
        OR LOWER(ddesc.long_title) LIKE '%septic%'
        OR LOWER(ddesc.long_title) LIKE '%hemorrhag%'
        OR LOWER(ddesc.long_title) LIKE '%haemorrhag%'
        OR LOWER(ddesc.long_title) LIKE '%bleed%'
        OR LOWER(ddesc.long_title) LIKE '%pulmonary embol%'
        OR LOWER(ddesc.long_title) LIKE '%embolism%'
        OR LOWER(ddesc.long_title) LIKE '%myocardial infarction%'
        OR LOWER(ddesc.long_title) LIKE '%acute myocardial infarction%'
        OR LOWER(ddesc.long_title) LIKE '%respiratory failure%'
        OR LOWER(ddesc.long_title) LIKE '%acute respiratory failure%'
        OR LOWER(ddesc.long_title) LIKE '%stroke%'
        OR LOWER(ddesc.long_title) LIKE '%cerebrovascular%'
      ) THEN 1 ELSE 0 END) AS has_major_complication
  FROM
    (SELECT DISTINCT hadm_id FROM high_comorb_cohort) hc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON dx.hadm_id = hc.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
      ON ddesc.icd_code = dx.icd_code
      AND COALESCE(CAST(ddesc.icd_version AS STRING), '') = COALESCE(CAST(dx.icd_version AS STRING), '')
  GROUP BY hc.hadm_id
),

-- 6) Build final cohort with outcomes and composite score
final_cohort AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    h.anchor_age,
    h.dod,
    h.comorbidity_count,
    -- 30-day mortality: in-hospital OR dod within 30 days of discharge
    CASE
      WHEN h.hospital_expire_flag = 1 THEN 1
      WHEN h.dod IS NOT NULL
           AND DATE_DIFF(DATE(h.dod), DATE(h.dischtime), DAY) BETWEEN 0 AND 30 THEN 1
      ELSE 0
    END AS death_within_30d,
    -- days to death for decedents (post-discharge date diff); NULL if no dod or dod <= dischtime
    CASE
      WHEN h.dod IS NOT NULL AND DATE(h.dod) > DATE(h.dischtime)
      THEN DATE_DIFF(DATE(h.dod), DATE(h.dischtime), DAY)
      ELSE NULL
    END AS days_to_death,
    COALESCE(hc.has_major_complication, 0) AS has_major_complication,
    -- simple composite score: comorbidity_count + age_points; age_points: bucketed by 5-year bands starting from 59
    (COALESCE(h.comorbidity_count,0)
      + CAST(FLOOR( (h.anchor_age - 59) / 5 ) AS INT64)
    ) AS composite_score
  FROM
    high_comorb_cohort h
    LEFT JOIN hadm_complications hc USING (hadm_id)
)

-- Final aggregated outputs
SELECT
  COUNT(*) AS cohort_size,
  SUM(death_within_30d) AS deaths_30d_count,
  ROUND( SAFE_DIVIDE(SUM(death_within_30d), COUNT(*)) * 100, 2) AS deaths_30d_percent,
  SUM(CASE WHEN has_major_complication = 1 THEN 1 ELSE 0 END) AS major_complication_count,
  ROUND( SAFE_DIVIDE(SUM(CASE WHEN has_major_complication = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100, 2) AS major_complication_percent,
  -- median survival among decedents (days from discharge to death), approximate median
  (SELECT
     IFNULL( (APPROX_QUANTILES(days_to_death, 2))[OFFSET(1)], NULL )
   FROM final_cohort fc2
   WHERE fc2.days_to_death IS NOT NULL
  ) AS median_days_to_death_for_decedents,
  -- composite score quartiles: APPROX_QUANTILES returns array [min, Q1, median, Q3, max] for n=4
  (APPROX_QUANTILES(composite_score, 4))[SAFE_OFFSET(1)] AS composite_q1,
  (APPROX_QUANTILES(composite_score, 4))[SAFE_OFFSET(2)] AS composite_median,
  (APPROX_QUANTILES(composite_score, 4))[SAFE_OFFSET(3)] AS composite_q3
FROM
  final_cohort;