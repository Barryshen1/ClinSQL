WITH pe_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.dod,
    -- Risk score (simplified PESI: age + cancer + CHF + CLD; no PE points)
    p.anchor_age + 
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        WHERE di.hadm_id = a.hadm_id 
        AND ((di.icd_version = 10 AND di.icd_code >= 'C00' AND di.icd_code <= 'C969') 
             OR (di.icd_version = 9 AND di.icd_code >= '140' AND di.icd_code <= '2089'))
      ) THEN 30 
      ELSE 0 
    END + 
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        WHERE di.hadm_id = a.hadm_id 
        AND ((di.icd_version = 10 AND di.icd_code LIKE 'I50%') 
             OR (di.icd_version = 9 AND di.icd_code LIKE '428%'))
      ) THEN 10 
      ELSE 0 
    END + 
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        WHERE di.hadm_id = a.hadm_id 
        AND ((di.icd_version = 10 AND (di.icd_code >= 'J40' AND di.icd_code <= 'J479')) 
             OR (di.icd_version = 9 AND di.icd_code >= '490' AND di.icd_code <= '5059'))
      ) THEN 10 
      ELSE 0 
    END AS risk_score,
    -- Outcomes
    CASE 
      WHEN p.dod IS NOT NULL AND p.dod <= DATE(a.admittime) + INTERVAL 90 DAY THEN 1 
      ELSE 0 
    END AS mort_90d,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        WHERE di.hadm_id = a.hadm_id 
        AND ((di.icd_version = 10 AND di.icd_code LIKE 'N17%') 
             OR (di.icd_version = 9 AND di.icd_code LIKE '584%'))
      ) THEN 1 
      ELSE 0 
    END AS aki_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        WHERE di.hadm_id = a.hadm_id 
        AND ((di.icd_version = 10 AND di.icd_code = 'J80') 
             OR (di.icd_version = 9 AND di.icd_code = '5185'))
      ) THEN 1 
      ELSE 0 
    END AS ards_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
      AND ((d.icd_version = 10 AND d.icd_code LIKE 'I26%') 
           OR (d.icd_version = 9 AND d.icd_code LIKE '4151%'))
    )
),
pe_quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM pe_cohort
),
general_cohort AS (
  SELECT 
    COUNT(*) AS total_gen,
    SUM(CASE 
      WHEN p.dod IS NOT NULL AND p.dod <= DATE(a.admittime) + INTERVAL 90 DAY THEN 1 
      ELSE 0 
    END) AS deaths_gen
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),
general_stats AS (
  SELECT deaths_gen * 1.0 / total_gen AS general_90d_mort
  FROM general_cohort
)
SELECT 
  pq.quintile,
  COUNT(*) AS n,
  SUM(pq.mort_90d) * 1.0 / COUNT(*) AS pe_90d_mort_rate,
  gs.general_90d_mort AS general_70_80f_90d_mort_comparison,
  SUM(pq.aki_flag) * 1.0 / COUNT(*) AS aki_rate,
  SUM(pq.ards_flag) * 1.0 / COUNT(*) AS ards_rate,
  APPROX_QUANTILES(CASE WHEN pq.mort_90d = 0 THEN pq.los_days END, [0.5])[OFFSET(0)] AS median_surv_los_days
FROM pe_quintiles pq
CROSS JOIN general_stats gs
GROUP BY pq.quintile, gs.general_90d_mort
ORDER BY quintile;