WITH male_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.hadm_id IS NOT NULL
),

per_hadm_cardiac_counts AS (
  SELECT
    ma.hadm_id,
    -- count distinct cardiac icd procedure codes per hospitalization;
    -- COUNT(DISTINCT ...) will ignore NULLs so hospitalizations with no matching cardiac
    -- procedures will yield 0
    COALESCE(
      COUNT(DISTINCT CASE
        WHEN REGEXP_CONTAINS(LOWER(d.long_title),
          r'(card|heart|coronar|angiopla|stent|pacemaker|valve|cabg|aort|mitral|tricuspid|myocard)') 
        THEN pr.icd_code
      END), 0) AS cardiac_proc_count
  FROM male_admissions ma
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON ma.hadm_id = pr.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  GROUP BY ma.hadm_id
)

SELECT
  -- approximate 75th percentile of distinct cardiac procedures per hospitalization
  APPROX_QUANTILES(cardiac_proc_count, 100)[OFFSET(75)] AS pct_75_cardiac_procs,
  COUNT(*) AS num_hospitalizations
FROM per_hadm_cardiac_counts;