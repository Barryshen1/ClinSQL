WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

dx_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  WHERE (
      (dx.icd_version = 9 AND (
          dx.icd_code LIKE '7865%'        -- chest pain
          OR dx.icd_code LIKE '410%'      -- AMI
      ))
      OR (dx.icd_version = 10 AND (
          dx.icd_code LIKE 'R07%'         -- chest pain
          OR dx.icd_code LIKE 'I21%'      -- AMI
      ))
  )
),

cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM dx_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON c.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON c.subject_id = adm.subject_id AND c.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
),

earliest_trop AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_items t
    ON l.itemid = t.itemid
  JOIN cohort c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.valuenum IS NOT NULL
),

initial_trop AS (
  SELECT subject_id, hadm_id, valuenum
  FROM earliest_trop
  WHERE rn = 1
),

categorized AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum <= 0.01 THEN 'normal'
      WHEN valuenum <= 0.03 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM initial_trop
)

SELECT
  category,
  COUNT(*) AS n,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS perc,
  ROUND(AVG(valuenum), 4) AS mean_trop,
  ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(50)], 4) AS median_trop,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 4) AS q1_trop,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 4) AS q3_trop
FROM categorized
GROUP BY category
ORDER BY category;