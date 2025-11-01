WITH t2dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'E11%')
     OR (icd_version = 9 AND icd_code LIKE '250%')
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
     OR (icd_version = 9 AND icd_code LIKE '428%')
),
cohort AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM t2dm_hadm)
    AND a.hadm_id IN (SELECT hadm_id FROM hf_hadm)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
glp1_events AS (
  SELECT e.hadm_id, e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.subject_id = ed.subject_id 
    AND e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  JOIN cohort c ON e.hadm_id = c.hadm_id
  WHERE LOWER(e.medication) LIKE '%liraglutide%'
     OR LOWER(e.medication) LIKE '%dulaglutide%'
     OR LOWER(e.medication) LIKE '%exenatide%'
     OR LOWER(e.medication) LIKE '%semaglutide%'
    AND (LOWER(ed.route) LIKE '%subcutaneous%' 
         OR LOWER(ed.route) LIKE '%intramuscular%' 
         OR LOWER(ed.route) LIKE '%intravenous%')
),
cohort_with_flags AS (
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM glp1_events g
        WHERE g.hadm_id = c.hadm_id
          AND g.charttime >= c.admittime
          AND g.charttime < c.admittime + INTERVAL 1 DAY
      ) THEN 1 ELSE 0 
    END AS first24_glp1,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM glp1_events g
        WHERE g.hadm_id = c.hadm_id
          AND g.charttime >= GREATEST(c.admittime, c.dischtime - INTERVAL 2 DAY)
          AND g.charttime < c.dischtime
      ) THEN 1 ELSE 0 
    END AS final48_glp1
  FROM cohort c
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(first24_glp1) AS first24_n,
  ROUND(SUM(first24_glp1) * 100.0 / COUNT(*), 2) AS first24_prevalence_pct,
  SUM(final48_glp1) AS final48_n,
  ROUND(SUM(final48_glp1) * 100.0 / COUNT(*), 2) AS final48_prevalence_pct,
  ROUND(
    (SUM(final48_glp1) * 100.0 / COUNT(*)) - (SUM(first24_glp1) * 100.0 / COUNT(*)), 
    2
  ) AS absolute_change_pct,
  CASE 
    WHEN SUM(first24_glp1) > 0 THEN 
      ROUND(
        ((SUM(final48_glp1) * 100.0 / COUNT(*)) - (SUM(first24_glp1) * 100.0 / COUNT(*))) 
        / (SUM(first24_glp1) * 100.0 / COUNT(*)) * 100, 
        2
      ) 
    ELSE NULL 
  END AS relative_change_pct
FROM cohort_with_flags;