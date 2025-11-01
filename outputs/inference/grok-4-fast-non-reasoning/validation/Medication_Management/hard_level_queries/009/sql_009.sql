WITH cohort AS (
  -- Base cohort: females 84-94 with AKI diagnosis (principal or secondary)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.seq_num <= CAST(2 AS INT64)  -- Principal + up to 1 secondary for AKI
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '584%') OR  -- AKI ICD-9
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'N17%')    -- AKI ICD-10
    )
),

all_admissions AS (
  -- All admissions for readmission calculation
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

readmissions AS (
  -- Flag readmissions with next admission details
  SELECT 
    a.*,
    next_adm.admittime AS next_admittime
  FROM all_admissions a
  LEFT JOIN all_admissions next_adm
    ON a.subject_id = next_adm.subject_id
    AND a.rn + 1 = next_adm.rn
),

mcs AS (
  -- Medication complexity score: unique drugs per admission
  SELECT 
    c.*,
    COALESCE(unique_drugs, 0) AS mcs_total
  FROM cohort c
  LEFT JOIN (
    SELECT 
      hadm_id,
      COUNT(DISTINCT LOWER(drug)) AS unique_drugs
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug IS NOT NULL
    GROUP BY hadm_id
  ) meds ON c.hadm_id = meds.hadm_id
),

outcomes AS (
  -- Compute outcomes including readmission flag
  SELECT 
    m.*,
    DATE_DIFF(TIMESTAMP(dischtime), TIMESTAMP(admittime), DAY) AS los,
    -- 30-day readmission flag
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND TIMESTAMP(next_admittime) <= TIMESTAMP_ADD(TIMESTAMP(dischtime), INTERVAL 30 DAY)
      THEN 1 ELSE 0 
    END AS readmit_flag,
    -- Anticoagulant-opioid coadmin flag (1 if both present)
    CASE 
      WHEN (
        SELECT COUNT(DISTINCT LOWER(drug)) 
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        WHERE p.hadm_id = m.hadm_id
          AND p.drug IS NOT NULL
          AND (
            LOWER(p.drug) LIKE '%heparin%' OR
            LOWER(p.drug) LIKE '%warfarin%' OR
            LOWER(p.drug) LIKE '%enoxaparin%' OR
            LOWER(p.drug) LIKE '%rivaroxaban%' OR
            LOWER(p.drug) LIKE '%apixaban%'
          )
      ) > 0 
      AND (
        SELECT COUNT(DISTINCT LOWER(drug)) 
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        WHERE p.hadm_id = m.hadm_id
          AND p.drug IS NOT NULL
          AND (
            LOWER(p.drug) LIKE '%morphine%' OR
            LOWER(p.drug) LIKE '%fentanyl%' OR
            LOWER(p.drug) LIKE '%oxycodone%' OR
            LOWER(p.drug) LIKE '%hydromorphone%' OR
            LOWER(p.drug) LIKE '%codeine%'
          )
      ) > 0 THEN 1 ELSE 0 
    END AS coadmin_flag
  FROM mcs m
  LEFT JOIN readmissions r
    ON m.subject_id = r.subject_id AND m.hadm_id = r.hadm_id
),

quintiles AS (
  -- Stratify by MCS quintiles (1 = highest complexity)
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY mcs_total DESC) AS quintile
  FROM outcomes
)

-- Final aggregates per quintile
SELECT 
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS avg_los_days,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag) * 100.0, COUNT(*)), 2) AS mortality_pct,
  ROUND(SAFE_DIVIDE(SUM(readmit_flag) * 100.0, COUNT(*)), 2) AS readmit_30d_pct,
  SUM(coadmin_flag) AS coadmin_count
FROM quintiles
GROUP BY quintile
ORDER BY quintile;