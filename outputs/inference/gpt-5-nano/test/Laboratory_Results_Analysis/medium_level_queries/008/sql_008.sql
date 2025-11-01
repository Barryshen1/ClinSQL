WITH acs_patients AS (
  -- Patients 87-97 year-old males admitted with ACS-related diagnoses
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      di.icd_code LIKE '410%'
      OR di.icd_code LIKE '411%'
      OR di.icd_code LIKE '413%'
      OR di.icd_code LIKE '414%'
    )
),
troponin_first AS (
  -- First Troponin T measurement during the admission
  SELECT le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),
cohort AS (
  -- Combine ACS cohort with the index Troponin T value
  SELECT a.hadm_id,
         a.subject_id,
         t.valuenum,
         CASE
           WHEN t.valuenum <= 0.01 THEN 'Normal/Minimal'
           WHEN t.valuenum > 0.01 AND t.valuenum <= 0.04 THEN 'Borderline'
           WHEN t.valuenum > 0.04 THEN 'Elevated'
           ELSE 'Unknown'
         END AS troponin_category,
         a.deathtime,
         a.dischtime
  FROM acs_patients ap
  JOIN troponin_first t ON t.hadm_id = ap.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = ap.hadm_id
),
total AS (
  SELECT COUNT(*) AS total_cohort FROM cohort
)
SELECT
  c.troponin_category,
  COUNT(*) AS n,
  SAFE_DIVIDE(COUNT(*), t.total_cohort) * 100 AS percent_of_cohort,
  SAFE_DIVIDE(SUM(
      CASE
        WHEN c.deathtime IS NOT NULL
             AND c.dischtime IS NOT NULL
             AND c.deathtime <= c.dischtime
        THEN 1 ELSE 0
      END
  ), COUNT(*)) AS in_hospital_mortality_rate
FROM cohort AS c
CROSS JOIN total AS t
GROUP BY c.troponin_category, t.total_cohort
ORDER BY c.troponin_category;