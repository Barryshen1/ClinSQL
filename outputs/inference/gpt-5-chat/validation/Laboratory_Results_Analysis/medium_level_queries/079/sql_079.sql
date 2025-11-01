WITH dx_cohort AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE ( (d.icd_version = 10 AND (
              d.icd_code LIKE 'R07%'  -- chest pain
              OR d.icd_code LIKE 'I21%' -- acute MI
            )
          )
       OR (d.icd_version = 9 AND (
              d.icd_code LIKE '7865%'  -- chest pain
              OR d.icd_code LIKE '410%'  -- acute MI
            )
          )
        )
),
female_age_cohort AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
cohort AS (
  SELECT DISTINCT fa.subject_id, fa.hadm_id
  FROM female_age_cohort fa
  JOIN dx_cohort dx
    ON fa.subject_id = dx.subject_id
   AND fa.hadm_id = dx.hadm_id
),
trop_lab AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  SELECT c.subject_id, c.hadm_id,
         t.valuenum AS initial_trop,
         ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY t.charttime) AS rn
  FROM cohort c
  JOIN trop_lab t
    ON c.subject_id = t.subject_id
   AND c.hadm_id = t.hadm_id
),
agg AS (
  SELECT 
    MIN(initial_trop) AS min_trop,
    MAX(initial_trop) AS max_trop,
    APPROX_QUANTILES(initial_trop, 100) AS quantiles
  FROM first_trop
  WHERE rn = 1
    AND initial_trop > 0.01
)
SELECT 
  min_trop,
  max_trop,
  quantiles[OFFSET(ROUND(0.25 * (ARRAY_LENGTH(quantiles)-1)))] AS p25_trop,
  quantiles[OFFSET(ROUND(0.50 * (ARRAY_LENGTH(quantiles)-1)))] AS p50_trop,
  quantiles[OFFSET(ROUND(0.75 * (ARRAY_LENGTH(quantiles)-1)))] AS p75_trop
FROM agg;