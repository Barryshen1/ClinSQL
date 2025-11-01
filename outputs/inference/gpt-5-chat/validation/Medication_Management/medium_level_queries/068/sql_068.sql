WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- age and gender filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),
dx AS (
  SELECT hadm_id,
    MAX(CASE WHEN ( (d.icd_version = 9 AND icd_code LIKE '250%')
                    OR (d.icd_version = 10 AND icd_code LIKE 'E11%') )
             THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN ( (d.icd_version = 9 AND icd_code LIKE '428%')
                    OR (d.icd_version = 10 AND icd_code LIKE 'I50%') )
             THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.has_t2dm = 1
    AND dx.has_hf = 1
),
presc AS (
  SELECT pr.hadm_id,
         pr.starttime,
         pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort_with_dx c
    ON pr.hadm_id = c.hadm_id
),
classified AS (
  SELECT p.hadm_id,
         CASE WHEN LOWER(pr.drug) LIKE '%glargine%'
                    OR LOWER(pr.drug) LIKE '%detemir%'
                    OR LOWER(pr.drug) LIKE '%degludec%'
                    OR LOWER(pr.drug) LIKE '%nph%' THEN 1 ELSE 0 END AS basal,
         CASE WHEN LOWER(pr.drug) LIKE '%lispro%'
                    OR LOWER(pr.drug) LIKE '%aspart%'
                    OR LOWER(pr.drug) LIKE '%glulisine%'
                    OR LOWER(pr.drug) LIKE '%regular insulin%' THEN 1 ELSE 0 END AS bolus,
         CASE WHEN LOWER(pr.drug) LIKE '%sliding%'
                    OR LOWER(pr.drug) LIKE '%scale%' THEN 1 ELSE 0 END AS sliding,
         pr.starttime
  FROM presc p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.hadm_id = pr.hadm_id 
   AND p.starttime = pr.starttime 
   AND p.drug = pr.drug
),
window_flags AS (
  SELECT c.hadm_id,
         MAX(CASE WHEN starttime >= c.admittime
                   AND starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
                  THEN basal ELSE 0 END) AS basal_first48,
         MAX(CASE WHEN starttime >= c.admittime
                   AND starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
                  THEN bolus ELSE 0 END) AS bolus_first48,
         MAX(CASE WHEN starttime >= c.admittime
                   AND starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
                  THEN sliding ELSE 0 END) AS sliding_first48,
         MAX(CASE WHEN starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
                   AND starttime <= c.dischtime
                  THEN basal ELSE 0 END) AS basal_last12,
         MAX(CASE WHEN starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
                   AND starttime <= c.dischtime
                  THEN bolus ELSE 0 END) AS bolus_last12,
         MAX(CASE WHEN starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
                   AND starttime <= c.dischtime
                  THEN sliding ELSE 0 END) AS sliding_last12
  FROM classified cl
  JOIN cohort_with_dx c
    ON cl.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),
window_cats AS (
  SELECT hadm_id,
         CASE 
           WHEN basal_first48 = 1 AND bolus_first48 = 1 THEN 'basal-bolus'
           WHEN basal_first48 = 1 THEN 'basal'
           WHEN bolus_first48 = 1 THEN 'bolus'
           WHEN sliding_first48 = 1 AND basal_first48 = 0 AND bolus_first48 = 0 THEN 'sliding-scale'
           ELSE 'none'
         END AS cat_first48,
         CASE 
           WHEN basal_last12 = 1 AND bolus_last12 = 1 THEN 'basal-bolus'
           WHEN basal_last12 = 1 THEN 'basal'
           WHEN bolus_last12 = 1 THEN 'bolus'
           WHEN sliding_last12 = 1 AND basal_last12 = 0 AND bolus_last12 = 0 THEN 'sliding-scale'
           ELSE 'none'
         END AS cat_last12
  FROM window_flags
),
counts AS (
  SELECT cat_first48 AS category,
         COUNT(*) AS n_first48
  FROM window_cats
  GROUP BY cat_first48
),
counts_last AS (
  SELECT cat_last12 AS category,
         COUNT(*) AS n_last12
  FROM window_cats
  GROUP BY cat_last12
),
n_total AS (
  SELECT COUNT(*) AS n
  FROM window_cats
),
percents AS (
  SELECT c.category,
         n_first48,
         ROUND(n_first48 / n_total.n * 100, 2) AS pct_first48,
         n_last12,
         ROUND(n_last12 / n_total.n * 100, 2) AS pct_last12,
         ROUND((n_last12 - n_first48) / n_total.n * 100, 2) AS net_change_pct
  FROM n_total
  FULL OUTER JOIN counts c
    ON TRUE
  FULL OUTER JOIN counts_last cl
    ON c.category = cl.category
)
SELECT category, pct_first48, pct_last12, net_change_pct
FROM percents
WHERE category IS NOT NULL;