WITH cohort AS (
  -- 1. Female, age 40-50
  SELECT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
         adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
),
dx AS (
  -- 2. Diagnosis filter: both neutropenia and fever codes
  SELECT hadm_id,
         MAX(CASE WHEN ( (icd_version = 9 AND icd_code IN ('2880')) 
                         OR (icd_version = 10 AND icd_code LIKE 'D70%') )
                  THEN 1 ELSE 0 END) AS has_neutropenia,
         MAX(CASE WHEN ( (icd_version = 9 AND icd_code IN ('7806')) 
                         OR (icd_version = 10 AND icd_code LIKE 'R50%') )
                  THEN 1 ELSE 0 END) AS has_fever
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_nf AS (
  -- 3. Keep only neutropenic fever cases
  SELECT c.*
  FROM cohort c
  JOIN dx d 
    ON c.hadm_id = d.hadm_id
  WHERE d.has_neutropenia = 1
    AND d.has_fever = 1
),
meds AS (
  -- 4. Medication complexity score: unique drugs in first 48h from admission
  SELECT p.hadm_id,
         COUNT(DISTINCT LOWER(TRIM(p.drug))) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort_nf c
    ON p.hadm_id = c.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND p.starttime >= c.admittime
  GROUP BY p.hadm_id
),
base AS (
  -- 5. Combine cohort with complexity score & LOS
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime,
         TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days,
         c.hospital_expire_flag,
         m.complexity_score
  FROM cohort_nf c
  LEFT JOIN meds m
    ON c.hadm_id = m.hadm_id
),
readm AS (
  -- 6. Flag 30-day readmissions
  SELECT a1.hadm_id,
         CASE WHEN COUNT(a2.hadm_id) > 0 THEN 1 ELSE 0 END AS readmit_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
   AND a2.admittime > a1.dischtime
   AND DATETIME_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
   AND a2.hadm_id != a1.hadm_id
  GROUP BY a1.hadm_id
),
scored AS (
  -- 7. Attach readmission flag
  SELECT b.*,
         IFNULL(r.readmit_30d,0) AS readmit_30d
  FROM base b
  LEFT JOIN readm r
    ON b.hadm_id = r.hadm_id
),
quartiles AS (
  -- 8. Assign quartiles based on complexity_score
  SELECT *,
         NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
  FROM scored
)
-- 9. Aggregate per quartile
SELECT complexity_quartile,
       COUNT(DISTINCT subject_id) AS patient_count,
       AVG(complexity_score) AS mean_score,
       MIN(complexity_score) AS min_score,
       MAX(complexity_score) AS max_score,
       AVG(los_days) AS mean_los_days,
       100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_pct,
       100.0 * SUM(readmit_30d) / COUNT(*) AS readmit_30d_pct
FROM quartiles
GROUP BY complexity_quartile
ORDER BY complexity_quartile;