WITH cohort_adm AS (
  -- female inpatients in the target age window with valid admit/discharge times
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

diag_flags AS (
  -- per admission, flag presence of diabetes and heart failure via diagnosis long_title
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabet%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    USING(icd_code, icd_version)
  GROUP BY di.hadm_id
),

cohort AS (
  -- admissions satisfying both diagnosis flags and the demographic filters
  SELECT c.*
  FROM cohort_adm c
  JOIN diag_flags df
    USING(hadm_id)
  WHERE df.has_diabetes = 1
    AND df.has_hf = 1
),

glp_pres_flags AS (
  -- for each admission in the cohort, determine if any GLP-1 RA prescription overlaps the first 48h and/or final 12h windows
  SELECT
    c.hadm_id,
    -- indicator for any GLP-1 RA overlapping first 48 hours from admittime
    MAX(
      CASE
        WHEN
          -- drug matches GLP-1 names/brands
          REGEXP_CONTAINS(LOWER(COALESCE(pr.drug, '')), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|byetta|victoza|trulicity|ozempic|rybelsus|adlyxin|tanzeum|mounjaro')
          -- overlap condition: start <= admittime + 48h AND (stoptime IS NULL OR stoptime >= admittime)
          AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
          AND (pr.stoptime IS NULL OR pr.stoptime >= c.admittime)
        THEN 1 ELSE 0
      END
    ) AS any_glp_first48,
    -- indicator for any GLP-1 RA overlapping final 12 hours before discharge
    MAX(
      CASE
        WHEN
          REGEXP_CONTAINS(LOWER(COALESCE(pr.drug, '')), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|byetta|victoza|trulicity|ozempic|rybelsus|adlyxin|tanzeum|mounjaro')
          -- overlap final 12h window: stoptime >= discharge-12h (or NULL) AND starttime <= dischtime AND starttime < dischtime
          AND pr.starttime <= c.dischtime
          AND (pr.stoptime IS NULL OR pr.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
          AND pr.starttime < c.dischtime
        THEN 1 ELSE 0
      END
    ) AS any_glp_final12
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
)

SELECT
  COUNT(1) AS cohort_n,
  SUM(IF(g.any_glp_first48 = 1, 1, 0)) AS n_glp_first48,
  ROUND(100.0 * SAFE_DIVIDE(SUM(IF(g.any_glp_first48 = 1, 1, 0)), COUNT(1)), 2) AS pct_glp_first48,
  SUM(IF(g.any_glp_final12 = 1, 1, 0)) AS n_glp_final12,
  ROUND(100.0 * SAFE_DIVIDE(SUM(IF(g.any_glp_final12 = 1, 1, 0)), COUNT(1)), 2) AS pct_glp_final12,
  -- absolute change in percentage points (final12 - first48)
  ROUND(
    100.0 * SAFE_DIVIDE(SUM(IF(g.any_glp_final12 = 1, 1, 0)), COUNT(1))
    -
    100.0 * SAFE_DIVIDE(SUM(IF(g.any_glp_first48 = 1, 1, 0)), COUNT(1))
  , 2) AS abs_change_pct_points,
  -- relative change (%) = (final - first) / first * 100 ; SAFE_DIVIDE handles division-by-zero (returns NULL)
  ROUND(
    100.0 * SAFE_DIVIDE(
      (
        SAFE_DIVIDE(SUM(IF(g.any_glp_final12 = 1, 1, 0)), COUNT(1))
        -
        SAFE_DIVIDE(SUM(IF(g.any_glp_first48 = 1, 1, 0)), COUNT(1))
      ),
      SAFE_DIVIDE(SUM(IF(g.any_glp_first48 = 1, 1, 0)), COUNT(1))
    )
  , 2) AS relative_change_percent
FROM glp_pres_flags g;