WITH postop_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND (
         LOWER(dd.long_title) LIKE '%postoperative%'
         OR LOWER(dd.long_title) LIKE '%postop%'
        )
),

-- 2) ICU vs Non-ICU grouping based on ICU stays
icugroups AS (
  SELECT h.hadm_id,
         CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS group_label
  FROM postop_hadm h
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.hadm_id = h.hadm_id
  -- Only keep admissions that actually had postoperative complications
  -- (the postop_hadm set already ensures that)
),

-- 3) LOS buckets per admission
los_buckets AS (
  SELECT g.hadm_id,
         g.group_label,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         CASE
           WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
           WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
           WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 8 THEN '>8'
           ELSE NULL
         END AS los_bucket
  FROM icugroups g
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = g.hadm_id
),

-- 4) Approximate Charlson score per admission (weight by condition)
-- We map a representative subset of ICD-9/ICD-10 codes to Charlson weights.
charlson_scores AS (
  SELECT di.hadm_id,
         SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '412%'))
                   OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
                 THEN 1 ELSE 0 END) AS w_MI_Cardiac,
         SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '428%') OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                  THEN 1 ELSE 0 END) AS w_CHF,
         SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%' OR di.icd_code LIKE '433%' OR di.icd_code LIKE '434%' OR di.icd_code LIKE '435%'))
                  OR (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' OR di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I64%' OR di.icd_code LIKE 'I65%' OR di.icd_code LIKE 'I66%' OR di.icd_code LIKE 'I69%'))
                 THEN 1 ELSE 0 END) AS w_CVA,
         SUM(CASE WHEN LOWER(dd.long_title) LIKE '%dementia%' THEN 1 ELSE 0 END) AS w_Dementia,
         SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '490%' OR di.icd_code LIKE '491%' OR di.icd_code LIKE '492%'))
                  OR (di.icd_version = 10 AND (di.icd_code LIKE 'J44%' OR di.icd_code LIKE 'J43%'))
                 THEN 1 ELSE 0 END) AS w_COPD,
         SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '250%')
                  AND LOWER(dd.long_title) LIKE '%without end-organ%'
                 THEN 1 ELSE 0 END) AS w_Diabetes_without_end_organ,
         SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '250%')
                  AND LOWER(dd.long_title) LIKE '%with end-organ%'
                 THEN 2 ELSE 0 END) AS w_Diabetes_with_end_organ,
         SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '580%' OR di.icd_code LIKE '581%' OR di.icd_code LIKE '582%' OR di.icd_code LIKE '583%' OR di.icd_code LIKE '584%' OR di.icd_code LIKE '585%' OR di.icd_code LIKE '586%' OR di.icd_code LIKE '587%' OR di.icd_code LIKE '588%' OR di.icd_code LIKE '589%'))
                  THEN 2 ELSE 0 END) AS w_Renal_disease,
         SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '195%' OR di.icd_code LIKE '196%' OR di.icd_code LIKE '197%' OR di.icd_code LIKE '198%'))
                  OR (di.icd_version = 10 AND (di.icd_code LIKE 'C77%' OR di.icd_code LIKE 'C78%' OR di.icd_code LIKE 'C79%'))
                 THEN 6 ELSE 0 END) AS w_Metastasis,
         SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '201%' OR di.icd_code LIKE '202%' OR di.icd_code LIKE '203%'))
                  OR (di.icd_version = 10 AND (di.icd_code LIKE 'C81%' OR di.icd_code LIKE 'C82%' OR di.icd_code LIKE 'C83%'))
                 THEN 2 ELSE 0 END) AS w_Leukemia_or_Lymphoma,
         SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '042%')
                  OR (di.icd_version = 10 AND di.icd_code LIKE 'B20%')
                 THEN 6 ELSE 0 END) AS w_AIDS
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),

charlson_combined AS (
  SELECT di.hadm_id,
         COALESCE(x.w_MI_Cardiac,0) +
         COALESCE(x.w_CHF,0) +
         COALESCE(x.w_CVA,0) +
         COALESCE(x.w_Dementia,0) +
         COALESCE(x.w_COPD,0) +
         COALESCE(x.w_Diabetes_without_end_organ,0) +
         COALESCE(x.w_Diabetes_with_end_organ,0) +
         COALESCE(x.w_Renal_disease,0) +
         COALESCE(x.w_Metastasis,0) +
         COALESCE(x.w_Leukemia_or_Lymphoma,0) +
         COALESCE(x.w_AIDS,0) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  LEFT JOIN (
     SELECT hadm_id,
            SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '412%'))
                              OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
                         THEN 1 ELSE 0 END) AS w_MI_Cardiac,
            SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '428%') OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') THEN 1 ELSE 0 END) AS w_CHF,
            SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%' OR di.icd_code LIKE '433%' OR di.icd_code LIKE '434%' OR di.icd_code LIKE '435%'))
                      OR (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' OR di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I64%' OR di.icd_code LIKE 'I65%' OR di.icd_code LIKE 'I66%' OR di.icd_code LIKE 'I69%'))
                    THEN 1 ELSE 0 END) AS w_CVA,
            SUM(CASE WHEN LOWER(dd.long_title) LIKE '%dementia%' THEN 1 ELSE 0 END) AS w_Dementia,
            SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '490%' OR di.icd_code LIKE '491%' OR di.icd_code LIKE '492%'))
                      OR (di.icd_version = 10 AND (di.icd_code LIKE 'J44%' OR di.icd_code LIKE 'J43%'))
                    THEN 1 ELSE 0 END) AS w_COPD,
            SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '250%')
                      AND LOWER(dd.long_title) LIKE '%without end-organ%' THEN 1 ELSE 0 END) AS w_Diabetes_without_end_organ,
            SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '250%')
                      AND LOWER(dd.long_title) LIKE '%with end-organ%' THEN 2 ELSE 0 END) AS w_Diabetes_with_end_organ,
            SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '580%' OR di.icd_code LIKE '581%' OR di.icd_code LIKE '582%' OR di.icd_code LIKE '583%' OR di.icd_code LIKE '584%' OR di.icd_code LIKE '585%' OR di.icd_code LIKE '586%' OR di.icd_code LIKE '587%' OR di.icd_code LIKE '588%' OR di.icd_code LIKE '589%'))
                      THEN 2 ELSE 0 END) AS w_Renal_disease,
            SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '195%' OR di.icd_code LIKE '196%' OR di.icd_code LIKE '197%' OR di.icd_code LIKE '198%'))
                      OR (di.icd_version = 10 AND (di.icd_code LIKE 'C77%' OR di.icd_code LIKE 'C78%' OR di.icd_code LIKE 'C79%'))
                    THEN 6 ELSE 0 END) AS w_Metastasis,
            SUM(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '201%' OR di.icd_code LIKE '202%' OR di.icd_code LIKE '203%'))
                      OR (di.icd_version = 10 AND (di.icd_code LIKE 'C81%' OR di.icd_code LIKE 'C82%' OR di.icd_code LIKE 'C83%'))
                    THEN 2 ELSE 0 END) AS w_Leukemia_or_Lymphoma,
            SUM(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '042%')
                      OR (di.icd_version = 10 AND di.icd_code LIKE 'B20%')
                    THEN 6 ELSE 0 END) AS w_AIDS
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
     JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
       ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
     GROUP BY hadm_id
  ) AS x
  ON di.hadm_id = x.hadm_id
)

-- 5) Put together final metrics per group
SELECT
  g.group_label AS group_label,
  COUNT(*) AS n_total,
  ROUND(100.0 * SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
  -- LOS bucket counts
  SUM(CASE WHEN lb.los_bucket = '1-3' THEN 1 ELSE 0 END) AS n_los_1_3,
  SUM(CASE WHEN lb.los_bucket = '4-7' THEN 1 ELSE 0 END) AS n_los_4_7,
  SUM(CASE WHEN lb.los_bucket = '>8' THEN 1 ELSE 0 END) AS n_los_8_plus,
  -- Charlson group counts
  SUM(CASE WHEN cc.charlson_score <= 3 THEN 1 ELSE 0 END) AS n_charlson_le3,
  SUM(CASE WHEN cc.charlson_score BETWEEN 4 AND 5 THEN 1 ELSE 0 END) AS n_charlson_45,
  SUM(CASE WHEN cc.charlson_score >= 6 THEN 1 ELSE 0 END) AS n_charlson_gt5,
  -- Median time-to-death
  APPROX_QUANTILES(td.time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
FROM icugroups AS g
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON a.hadm_id = g.hadm_id
LEFT JOIN los_buckets lb
  ON lb.hadm_id = g.hadm_id
LEFT JOIN charlson_scores cc
  ON cc.hadm_id = g.hadm_id
LEFT JOIN charlson_combined cc2
  ON cc2.hadm_id = g.hadm_id
LEFT JOIN (
  SELECT hadm_id,
         TIMESTAMP_DIFF(deathtime, admittime, DAY) AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hospital_expire_flag = 1
) AS td
  ON td.hadm_id = g.hadm_id
GROUP BY g.group_label
ORDER BY g.group_label;