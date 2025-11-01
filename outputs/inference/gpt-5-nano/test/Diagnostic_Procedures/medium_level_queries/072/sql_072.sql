WITH pancreatitis_by_hadm AS (
  -- Identify admissions with pancreatitis and whether it's primary (seq_num = 1)
  SELECT di.hadm_id,
         MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS pancre_primary
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS diag
    ON di.icd_code = diag.icd_code
   AND di.icd_version = diag.icd_version
  WHERE LOWER(diag.long_title) LIKE '%pancreatit%'
  GROUP BY di.hadm_id
),
cohort AS (
  -- Filter to women age 52-62
  SELECT p.hadm_id,
         pan.pancre_primary
  FROM pancreatitis_by_hadm AS pan
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS p
    ON p.hadm_id = pan.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = p.subject_id
  WHERE pat.gender = 'F' AND pat.anchor_age BETWEEN 52 AND 62
),
days_and_counts AS (
  -- Compute days band per admission
  SELECT c.hadm_id,
         c.pancre_primary,
         CASE
           WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
           WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 5 AND 8 THEN '5-8'
           ELSE NULL
         END AS days_band
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = c.hadm_id
),
proc_counts AS (
  -- Count procedures per admission (0 if none)
  SELECT d.hadm_id,
         d.pancre_primary,
         d.days_band,
         SUM(IF(pc.hadm_id IS NOT NULL, 1, 0)) AS proc_count
  FROM days_and_counts d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
    ON pc.hadm_id = d.hadm_id
  GROUP BY d.hadm_id, d.pancre_primary, d.days_band
  HAVING d.days_band IS NOT NULL
)
SELECT days_band,
       pancre_primary,
       AVG(proc_count) AS mean_procedures,
       MIN(proc_count) AS min_procedures,
       MAX(proc_count) AS max_procedures
FROM proc_counts
GROUP BY days_band, pancre_primary
ORDER BY days_band, pancre_primary;