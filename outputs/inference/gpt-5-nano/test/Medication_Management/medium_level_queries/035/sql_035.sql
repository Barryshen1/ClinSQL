WITH cohort_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

-- Keep only admissions that have both a diabetes diagnosis and a heart failure diagnosis
cohort_diag AS (
  SELECT cb.subject_id,
         cb.hadm_id,
         cb.admittime,
         cb.dischtime
  FROM cohort_base AS cb
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = cb.subject_id
   AND di.hadm_id = cb.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  GROUP BY cb.subject_id, cb.hadm_id, cb.admittime, cb.dischtime
  HAVING
    SUM(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) > 0
    AND
    SUM(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' OR LOWER(dd.long_title) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) > 0
),

-- GLP-1 RA prescriptions in the first 48 hours after admission
glp1_first48 AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(p.drug), '(liraglutide|exenatide|dulaglutide|lixisenatide|semaglutide|albiglutide)') THEN 1 ELSE 0 END) AS has_glp1_first48
  FROM cohort_diag AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = c.subject_id
   AND p.hadm_id = c.hadm_id
   AND p.starttime >= c.admittime
   AND p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),

-- GLP-1 RA prescriptions in the final 12 hours before discharge
glp1_final12 AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(p.drug), '(liraglutide|exenatide|dulaglutide|lixisenatide|semaglutide|albiglutide)') THEN 1 ELSE 0 END) AS has_glp1_final12
  FROM cohort_diag AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = c.subject_id
   AND p.hadm_id = c.hadm_id
   AND p.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
   AND p.starttime <= c.dischtime
  GROUP BY c.hadm_id
),

summary AS (
  SELECT
    COUNT(*) AS total_inpatients,
    SUM(COALESCE(f.has_glp1_first48, 0)) AS n_first48,
    SUM(COALESCE(t.has_glp1_final12, 0)) AS n_final12
  FROM cohort_diag AS c
  LEFT JOIN glp1_first48 AS f ON f.hadm_id = c.hadm_id
  LEFT JOIN glp1_final12 AS t ON t.hadm_id = c.hadm_id
)

SELECT
  total_inpatients,
  ROUND(100.0 * n_first48 / NULLIF(total_inpatients, 0), 2) AS prevalence_first48_percent,
  ROUND(100.0 * n_final12 / NULLIF(total_inpatients, 0), 2) AS prevalence_final12_percent,
  ROUND(100.0 * (n_final12 - n_first48) / NULLIF(total_inpatients, 0), 2) AS absolute_change_percent_points,
  ROUND(
        CASE
          WHEN n_first48 > 0 THEN 100.0 * (n_final12 - n_first48) / NULLIF(n_first48, 0)
          ELSE NULL
        END, 2) AS relative_change_percent
FROM summary;