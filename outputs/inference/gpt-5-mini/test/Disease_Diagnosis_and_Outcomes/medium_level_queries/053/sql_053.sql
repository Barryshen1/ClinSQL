WITH diagnoses_agg AS (
  -- Aggregate diagnoses per admission to detect aspiration vs other pneumonia
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(diag.long_title) LIKE '%aspiration%' THEN 1 ELSE 0 END) AS has_aspiration,
    MAX(CASE WHEN LOWER(diag.long_title) LIKE '%pneumonia%' THEN 1 ELSE 0 END) AS has_pneumonia,
    -- comorbidity count: distinct diagnosis codes on the admission excluding pneumonia-labeled diagnoses
    COUNT(DISTINCT CASE WHEN LOWER(diag.long_title) NOT LIKE '%pneumonia%' THEN d.icd_code ELSE NULL END) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON
    d.icd_code = diag.icd_code
    AND d.icd_version = diag.icd_version
  GROUP BY
    d.hadm_id
),

admissions_cohort AS (
  -- Base admissions filtered to male 39-49 and joined with diagnosis flags
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    da.has_aspiration,
    da.has_pneumonia,
    da.comorbidity_count,
    -- length of stay in days as calendar days inclusive
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 AS los_days,
    -- LOS category
    CASE
      WHEN DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
      ELSE '8+'
    END AS los_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  LEFT JOIN
    diagnoses_agg da
  ON
    a.hadm_id = da.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    -- ensure we have diagnosis info (has_pneumonia or has_aspiration will be used later)
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

cohort_with_pneumonia AS (
  -- Keep only admissions with pneumonia and classify type (aspiration takes precedence)
  SELECT
    ac.*,
    CASE
      WHEN ac.has_aspiration = 1 THEN 'aspiration'
      WHEN ac.has_pneumonia = 1 THEN 'community_acquired'
      ELSE NULL
    END AS pneumonia_type
  FROM
    admissions_cohort ac
  WHERE
    -- require at least some pneumonia diagnosis
    (ac.has_aspiration = 1 OR ac.has_pneumonia = 1)
),

cohort_with_icu_day1 AS (
  -- Determine whether there is ICU exposure on day 1 of the admission
  SELECT
    c.*,
    -- Day 1 interval is [admittime, admittime + 1 day)
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE
        icu.hadm_id = c.hadm_id
        AND icu.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
        AND icu.outtime > c.admittime
    ) THEN TRUE ELSE FALSE END AS icu_day1
  FROM
    cohort_with_pneumonia c
),

aggregated AS (
  -- Aggregate statistics by LOS category, ICU day1 status, and pneumonia type
  SELECT
    los_category,
    icu_day1,
    pneumonia_type,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    -- mortality percentage
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100.0 AS mortality_pct,
    -- average comorbidity count per admission in the group
    AVG(COALESCE(comorbidity_count,0)) AS avg_comorbidity_count
  FROM
    cohort_with_icu_day1
  GROUP BY
    los_category,
    icu_day1,
    pneumonia_type
)

-- Final pivot and difference calculations
SELECT
  los_category,
  IF(icu_day1, 'ICU day1', 'No ICU day1') AS icu_day1_status,

  -- Aspiration columns
  COALESCE(MAX(CASE WHEN pneumonia_type = 'aspiration' THEN n_admissions END), 0) AS n_adm_aspiration,
  COALESCE(MAX(CASE WHEN pneumonia_type = 'aspiration' THEN n_deaths END), 0) AS n_deaths_aspiration,
  COALESCE(MAX(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_pct END), 0.0) AS mortality_pct_aspiration,
  COALESCE(MAX(CASE WHEN pneumonia_type = 'aspiration' THEN avg_comorbidity_count END), 0.0) AS avg_comorbidity_aspiration,

  -- Community-acquired columns
  COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN n_admissions END), 0) AS n_adm_community_acquired,
  COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN n_deaths END), 0) AS n_deaths_community_acquired,
  COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_pct END), 0.0) AS mortality_pct_community_acquired,
  COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN avg_comorbidity_count END), 0.0) AS avg_comorbidity_community_acquired,

  -- Absolute and relative differences (aspiration minus community-acquired)
  -- Absolute difference in percentage points
  (COALESCE(MAX(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_pct END), 0.0)
   - COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_pct END), 0.0)
  ) AS absolute_diff_pct_points,

  -- Relative difference: ((asp - cap) / cap) * 100. NULL if cap mortality is zero.
  CASE
    WHEN COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_pct END), 0.0) = 0 THEN NULL
    ELSE
      100.0 * (
        COALESCE(MAX(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_pct END), 0.0)
        - COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_pct END), 0.0)
      ) / COALESCE(MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_pct END), 0.0)
  END AS relative_diff_percent

FROM
  aggregated
GROUP BY
  los_category,
  icu_day1
ORDER BY
  -- order by LOS bucket then ICU status
  CASE los_category WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END,
  icu_day1 DESC;