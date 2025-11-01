WITH
-- Step 1: Base admissions for female patients age 57-67
female_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

-- Step 2: Identify sepsis and septic shock diagnoses
dx_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_shock,
    MAX(CASE 
          WHEN LOWER(d.long_title) LIKE '%sepsis%' 
               AND NOT LOWER(d.long_title) LIKE '%shock%' 
          THEN 1 
          ELSE 0 
        END) AS has_sepsis
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      USING (icd_code, icd_version)
  GROUP BY
    di.subject_id, di.hadm_id
),

-- Step 3: Classify admissions as sepsis / septic shock
sepsis_cohort AS (
  SELECT
    fa.*,
    CASE
      WHEN df.has_shock = 1 THEN 'septic shock'
      WHEN df.has_sepsis = 1 THEN 'sepsis without shock'
      ELSE NULL
    END AS sepsis_type
  FROM
    female_adm fa
    LEFT JOIN dx_flags df
      USING (subject_id, hadm_id)
  WHERE
    df.has_shock = 1 OR df.has_sepsis = 1
),

-- Step 4: Placeholder CTE for Charlson scores; in practice compute from diagnoses_icd
charlson_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- placeholder: replace with real Charlson computation
    CAST(FLOOR(RAND() * 10) AS INT64) AS charlson_score
  FROM
    sepsis_cohort
),

-- Step 5: Combine and bucket LOS and Charlson
buckets AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.sepsis_type,
    CASE
      WHEN sc.los_days <= 7 THEN '≤7 days'
      ELSE '>7 days'
    END AS los_group,
    CASE
      WHEN cs.charlson_score <= 3 THEN '≤3'
      WHEN cs.charlson_score BETWEEN 4 AND 5 THEN '4–5'
      ELSE '>5'
    END AS charlson_group,
    sc.hospital_expire_flag
  FROM
    sepsis_cohort sc
    JOIN charlson_scores cs
      USING (subject_id, hadm_id)
),

-- Step 6: Aggregate mortality
agg AS (
  SELECT
    los_group,
    charlson_group,
    sepsis_type,
    COUNT(*) AS admissions,
    SUM(hospital_expire_flag) AS deaths,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100.0 AS mortality_pct
  FROM
    buckets
  GROUP BY
    los_group, charlson_group, sepsis_type
),

-- Step 7: Pivot sepsis_type into columns and compute differences
pivoted AS (
  SELECT
    a.los_group,
    a.charlson_group,
    a.admissions      AS adm_sepsis,
    a.deaths          AS death_sepsis,
    a.mortality_pct   AS pct_sepsis,
    b.admissions      AS adm_shock,
    b.deaths          AS death_shock,
    b.mortality_pct   AS pct_shock
  FROM
    agg a
    JOIN agg b
      USING (los_group, charlson_group)
  WHERE
    a.sepsis_type = 'sepsis without shock'
    AND b.sepsis_type = 'septic shock'
)

SELECT
  los_group,
  charlson_group,
  pct_sepsis,
  pct_shock,
  (pct_shock - pct_sepsis) AS absolute_diff_pct,
  SAFE_DIVIDE(pct_shock - pct_sepsis, NULLIF(pct_sepsis, 0)) * 100.0 AS relative_diff_pct
FROM
  pivoted
ORDER BY
  los_group,
  charlson_group;