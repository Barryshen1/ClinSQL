WITH patients_elig AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
    -- Diagnoses: diabetes and heart failure
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E10%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '428')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
meds AS (
  SELECT 
    pe.hadm_id,
    pe.drug,
    pe.starttime,
    pe.stoptime,
    -- Classify drug type
    CASE
      WHEN LOWER(pe.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(pe.drug) IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 'rosiglitazone',
        'sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin',
        'empagliflozin', 'dapagliflozin', 'canagliflozin',
        'glipizide xl', 'metformin er', 'repaglinide', 'nateglinide'
      ) OR LOWER(pe.drug) LIKE '%metformin%' 
        OR LOWER(pe.drug) LIKE '%gliptin%' 
        OR LOWER(pe.drug) LIKE '%gliflozin%' 
        OR LOWER(pe.drug) LIKE '%sulfonylurea%'
        OR LOWER(pe.drug) LIKE '%thiazolidinedione%'
      THEN 'oral_agent'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pe
  JOIN patients_elig pe_adm ON pe.hadm_id = pe_adm.hadm_id
  WHERE pe.drug IS NOT NULL
    AND pe.starttime IS NOT NULL
),
time_windows AS (
  SELECT 
    hadm_id,
    -- Early window: first 48 hours
    admittime AS early_start,
    admittime + INTERVAL 48 HOUR AS early_end,
    -- Late window: final 72 hours
    dischtime - INTERVAL 72 HOUR AS late_start,
    dischtime AS late_end
  FROM patients_elig
),
meds_in_windows AS (
  SELECT 
    m.hadm_id,
    m.drug_class,
    -- Early window: any prescription started or ongoing in first 48h
    MAX(CASE WHEN m.starttime < tw.early_end 
              AND (m.stoptime IS NULL OR m.stoptime > tw.early_start)
         THEN 1 ELSE 0 END) AS early_use,
    -- Late window: any prescription started or ongoing in final 72h
    MAX(CASE WHEN m.starttime < tw.late_end 
              AND (m.stoptime IS NULL OR m.stoptime > tw.late_start)
         THEN 1 ELSE 0 END) AS late_use,
    -- Initiation: started in window but not before
    MAX(CASE WHEN m.starttime >= tw.early_start AND m.starttime < tw.early_end
              AND (m.stoptime IS NULL OR m.stoptime > m.starttime)
         THEN 1 ELSE 0 END) AS early_initiation,
    MAX(CASE WHEN m.starttime >= tw.late_start AND m.starttime < tw.late_end
              AND (m.stoptime IS NULL OR m.stoptime > m.starttime)
         THEN 1 ELSE 0 END) AS late_initiation
  FROM meds m
  JOIN time_windows tw ON m.hadm_id = tw.hadm_id
  WHERE m.drug_class IN ('insulin', 'oral_agent')
  GROUP BY m.hadm_id, m.drug_class
),
summary_stats AS (
  SELECT
    drug_class,
    AVG(early_use) * 100 AS early_usage_rate,
    AVG(late_use) * 100 AS late_usage_rate,
    AVG(early_initiation) * 100 AS early_initiation_rate,
    AVG(late_initiation) * 100 AS late_initiation_rate
  FROM meds_in_windows
  GROUP BY drug_class
)
SELECT
  drug_class,
  early_initiation_rate AS initiation_rate_0_48h_pct,
  late_initiation_rate AS initiation_rate_final_72h_pct,
  (late_usage_rate - early_usage_rate) AS net_change_pp
FROM summary_stats
ORDER BY drug_class;