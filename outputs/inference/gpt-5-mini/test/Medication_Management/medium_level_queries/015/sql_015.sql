WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- Diabetes diagnosis (ICD-10 E10/E11, ICD-9 250, or long_title containing 'diabetes')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(COALESCE(dic.long_title, '')) LIKE '%diabetes%'
          OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'
          OR d.icd_code LIKE '250%'
        )
    )
    -- Acute heart failure diagnosis (ICD-10 I50*, ICD-9 428*, or long_title containing 'heart failure')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(COALESCE(dic.long_title, '')) LIKE '%heart failure%'
          OR d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%'
        )
    )
),

-- Consolidate medication records from hospital sources
meds_raw AS (
  -- prescriptions table (drug, starttime, stoptime)
  SELECT
    hadm_id,
    LOWER(COALESCE(drug, '')) AS drug_name,
    starttime AS med_start,
    stoptime AS med_stop
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  -- pharmacy dispensation records (medication, starttime, stoptime)
  SELECT
    hadm_id,
    LOWER(COALESCE(medication, '')) AS drug_name,
    starttime AS med_start,
    stoptime AS med_stop
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  -- emar medication administrations (medication, charttime)
  SELECT
    hadm_id,
    LOWER(COALESCE(medication, '')) AS drug_name,
    charttime AS med_start,
    NULL AS med_stop
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE hadm_id IS NOT NULL
),

-- Classify meds into requested antidiabetic classes by name patterns
meds_class AS (
  SELECT
    m.*,
    CASE
      WHEN REGEXP_CONTAINS(m.drug_name, r'(insulin|aspart|lispro|glargine|detemir|degludec)') THEN 'Insulin'
      WHEN REGEXP_CONTAINS(m.drug_name, r'metformin') THEN 'Metformin'
      WHEN REGEXP_CONTAINS(m.drug_name, r'(glipizide|glyburide|glibenclamide|glimepiride|tolbutamide|chlorpropamide)') THEN 'Sulfonylurea'
      WHEN REGEXP_CONTAINS(m.drug_name, r'(sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin)') THEN 'DPP-4'
      WHEN REGEXP_CONTAINS(m.drug_name, r'(empagliflozin|dapagliflozin|canagliflozin|ertugliflozin)') THEN 'SGLT2'
      WHEN REGEXP_CONTAINS(m.drug_name, r'(liraglutide|dulaglutide|exenatide|semaglutide|albiglutide|lixisenatide)') THEN 'GLP-1'
      WHEN REGEXP_CONTAINS(m.drug_name, r'(pioglitazone|rosiglitazone|troglitazone)') THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM meds_raw m
  WHERE m.drug_name != ''
    -- keep only meds that match any of the targets (pre-filter)
    AND REGEXP_CONTAINS(
      m.drug_name,
      r'(insulin|aspart|lispro|glargine|detemir|degludec|metformin|glipizide|glyburide|glibenclamide|glimepiride|tolbutamide|chlorpropamide|sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin|empagliflozin|dapagliflozin|canagliflozin|ertugliflozin|liraglutide|dulaglutide|exenatide|semaglutide|albiglutide|lixisenatide|pioglitazone|rosiglitazone|troglitazone)'
    )
),

-- Determine whether each med overlaps the first-24h and final-12h windows for the admission
meds_in_windows AS (
  SELECT
    c.hadm_id,
    mc.drug_class,
    mc.med_start,
    mc.med_stop,
    -- first 24h overlap: med_start <= admittime+24h AND (med_stop IS NULL OR med_stop >= admittime)
    CASE
      WHEN mc.med_start IS NOT NULL
       AND mc.med_start <= (c.admittime + INTERVAL 24 HOUR)
       AND (mc.med_stop IS NULL OR mc.med_stop >= c.admittime)
      THEN 1 ELSE 0
    END AS in_first_24,
    -- final 12h overlap: med_start <= dischtime AND (med_stop IS NULL OR med_stop >= dischtime-12h)
    CASE
      WHEN mc.med_start IS NOT NULL
       AND mc.med_start <= c.dischtime
       AND (mc.med_stop IS NULL OR mc.med_stop >= (c.dischtime - INTERVAL 12 HOUR))
      THEN 1 ELSE 0
    END AS in_final_12
  FROM cohort c
  JOIN meds_class mc
    ON mc.hadm_id = c.hadm_id
),

-- For each hadm_id and drug_class, deduplicate into presence flags per window
hadm_class_flags AS (
  SELECT
    hadm_id,
    drug_class,
    MAX(in_first_24) AS first24_flag,
    MAX(in_final_12) AS final12_flag
  FROM meds_in_windows
  GROUP BY hadm_id, drug_class
),

total_admissions AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions FROM cohort
)

-- Final aggregation: counts and percentages per class
SELECT
  cls.drug_class,
  COALESCE(SUM(CASE WHEN hcf.first24_flag = 1 THEN 1 ELSE 0 END), 0) AS first24_n,
  COALESCE(SUM(CASE WHEN hcf.final12_flag = 1 THEN 1 ELSE 0 END), 0) AS final12_n,
  tot.total_admissions,
  SAFE_DIVIDE(100.0 * COALESCE(SUM(CASE WHEN hcf.first24_flag = 1 THEN 1 ELSE 0 END), 0), tot.total_admissions) AS first24_pct,
  SAFE_DIVIDE(100.0 * COALESCE(SUM(CASE WHEN hcf.final12_flag = 1 THEN 1 ELSE 0 END), 0), tot.total_admissions) AS final12_pct,
  SAFE_DIVIDE(
    100.0 * (
      COALESCE(SUM(CASE WHEN hcf.final12_flag = 1 THEN 1 ELSE 0 END), 0)
      - COALESCE(SUM(CASE WHEN hcf.first24_flag = 1 THEN 1 ELSE 0 END), 0)
    ),
    tot.total_admissions
  ) AS net_change_pp
FROM (
  SELECT 'Insulin' AS drug_class UNION ALL SELECT 'Metformin' UNION ALL SELECT 'Sulfonylurea'
  UNION ALL SELECT 'DPP-4' UNION ALL SELECT 'SGLT2' UNION ALL SELECT 'GLP-1' UNION ALL SELECT 'TZD'
) cls
LEFT JOIN hadm_class_flags hcf
  ON hcf.drug_class = cls.drug_class
CROSS JOIN total_admissions tot
GROUP BY cls.drug_class, tot.total_admissions
ORDER BY cls.drug_class;