WITH cohort AS (
  -- Base cohort: females 70-80 with primary lower GI bleed admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'K92%'  -- Lower GI bleed (hemorrhage of GI tract)
    AND d.seq_num = 1  -- Primary diagnosis
    AND a.admittime >= '2008-01-01'  -- MIMIC-IV range
),

-- 90-day mortality flag
mortality_flags AS (
  SELECT 
    c.*,
    CASE 
      WHEN c.hospital_expire_flag = 1 
        OR (c.dod IS NOT NULL AND c.dod > c.admittime AND c.dod <= TIMESTAMP_ADD(c.admittime, INTERVAL 90 DAY))
      THEN 1 ELSE 0 
    END AS died_90d
  FROM cohort c
),

-- Simplified risk score components (age + comorbidities + emergency + prior adm)
risk_scores AS (
  SELECT 
    m.*,
    -- Age component
    (m.anchor_age - 70) AS age_score,
    -- Comorbidities (Charlson-like: select key codes)
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc 
        WHERE dc.subject_id = m.subject_id 
          AND dc.hadm_id = m.hadm_id 
          AND (dc.icd_code LIKE 'I50%'  -- Heart failure
            OR dc.icd_code LIKE 'N18%'  -- CKD
            OR dc.icd_code LIKE 'C%'    -- Cancer
            OR dc.icd_code LIKE 'I09%' OR dc.icd_code LIKE 'I11%' OR dc.icd_code LIKE 'I27%' OR dc.icd_code LIKE 'I42%')  -- Other CCI
      ) THEN 5 ELSE 0  -- Weighted points
    END AS comp_score,
    -- Emergency admission
    CASE WHEN m.admission_type = 'EMERGENCY' THEN 2 ELSE 0 END AS emerg_score,
    -- Prior admission in 1 year
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.admissions` pa
        WHERE pa.subject_id = m.subject_id
          AND pa.admittime < m.admittime
          AND pa.admittime >= TIMESTAMP_SUB(m.admittime, INTERVAL 365 DAY)
          AND pa.hospital_expire_flag = 0
      ) THEN 3 ELSE 0 
    END AS prior_score
  FROM mortality_flags m
),

scored_cohort AS (
  SELECT 
    *,
    -- Composite score (normalize to 0-100 roughly)
    LEAST(100, age_score + comp_score + emerg_score + prior_score) AS risk_score
  FROM risk_scores
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM scored_cohort
),

-- Major complications (in-hospital post-admission)
complications AS (
  SELECT 
    q.subject_id,
    q.hadm_id,
    -- AKI: Creatinine >=1.5x baseline (first post-adm creat >1.2 mg/dL threshold simplified)
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
          ON l.itemid = li.itemid 
        WHERE l.subject_id = q.subject_id 
          AND l.hadm_id = q.hadm_id
          AND li.label LIKE '%creatinine%serum%'
          AND l.charttime >= q.admittime 
          AND l.charttime <= q.dischtime
          AND l.valuenum >= 1.5  -- Simplified threshold (mg/dL); assume baseline ~1.0
          AND l.valueuom = 'mg/dL'
      ) THEN 1 ELSE 0 
    END AS has_aki,
    -- Transfusion: Blood products
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.inputevents` i 
        INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
          ON i.itemid = di.itemid 
        WHERE i.subject_id = q.subject_id 
          AND i.hadm_id = q.hadm_id
          AND (di.label LIKE '%blood%' OR di.label LIKE '%rbc%' OR di.label LIKE '%packed%')
          AND i.starttime >= q.admittime 
          AND i.starttime <= q.dischtime
          AND i.amount > 0
      ) THEN 1 ELSE 0 
    END AS has_transfusion,
    -- Reoperation: GI procedures
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
        WHERE proc.subject_id = q.subject_id 
          AND proc.hadm_id = q.hadm_id
          AND proc.icd_version = '10'
          AND proc.icd_code LIKE '0D1%'  -- GI repair/excision
          AND DATE(proc.chartdate) >= DATE(q.admittime) 
          AND DATE(proc.chartdate) <= DATE(q.dischtime)
      ) THEN 1 ELSE 0 
    END AS has_reop,
    -- Sepsis diagnosis
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ds 
        WHERE ds.subject_id = q.subject_id 
          AND ds.hadm_id = q.hadm_id
          AND ds.icd_version = '10'
          AND ds.icd_code LIKE 'A41%'  -- Sepsis
          AND ds.seq_num > 1  -- Secondary to avoid admission dx
      ) THEN 1 ELSE 0 
    END AS has_sepsis
  FROM quintiles q
),

final_cohort AS (
  SELECT 
    q.*,
    comp.* EXCEPT (subject_id, hadm_id),
    -- Composite complication flag (any major)
    CASE 
      WHEN comp.has_aki = 1 OR comp.has_transfusion = 1 
        OR comp.has_reop = 1 OR comp.has_sepsis = 1 
      THEN 1 ELSE 0 
    END AS has_complication,
    -- LOS for 90-day survivors
    CASE 
      WHEN q.died_90d = 0 
      THEN DATE_DIFF(DATE(q.dischtime), DATE(q.admittime), DAY)
      ELSE NULL 
    END AS los_days
  FROM quintiles q
  INNER JOIN complications comp 
    ON q.subject_id = comp.subject_id AND q.hadm_id = comp.hadm_id
)

-- Aggregates by quintile
SELECT 
  quintile,
  COUNT(*) AS N,
  ROUND(AVG(died_90d) * 100, 1) AS mortality_90d_rate_pct,
  ROUND(AVG(has_complication) * 100, 1) AS major_comp_rate_pct,
  PERCENTILE_CONT(los_days, 0.5) IGNORE NULLS AS median_los_days_among_survivors
FROM final_cohort
GROUP BY quintile
ORDER BY quintile;