WITH cohort AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) >= 48
), filtered_cohort AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime
  FROM cohort
  WHERE age_at_admit BETWEEN 59 AND 69
)
SELECT
  COUNT(*) AS total_admissions,
  SUM(flag_48h) AS count_48h,
  SUM(flag_12h) AS count_12h,
  ROUND(100.0 * SUM(flag_48h) / COUNT(*), 2) AS prevalence_48h,
  ROUND(100.0 * SUM(flag_12h) / COUNT(*), 2) AS prevalence_12h,
  ROUND(ABS(100.0 * SUM(flag_48h) / COUNT(*) - 100.0 * SUM(flag_12h) / COUNT(*)), 2) AS absolute_pp_difference
FROM (
  SELECT 
    fc.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e
      WHERE e.hadm_id = fc.hadm_id
        AND e.charttime >= fc.admittime
        AND e.charttime < TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)
        AND REGEXP_CONTAINS(LOWER(e.medication), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide')
    ) THEN 1 ELSE 0 END AS flag_48h,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e
      WHERE e.hadm_id = fc.hadm_id
        AND e.charttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 12 HOUR)
        AND e.charttime <= fc.dischtime
        AND REGEXP_CONTAINS(LOWER(e.medication), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide')
    ) THEN 1 ELSE 0 END AS flag_12h
  FROM filtered_cohort fc
) t;  -- Added alias 't' for the subquery;