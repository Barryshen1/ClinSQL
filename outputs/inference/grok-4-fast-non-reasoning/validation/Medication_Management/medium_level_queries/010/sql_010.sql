WITH cohort AS (
  -- Base cohort: females 67-77 with T2DM and HF (both required)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON p.subject_id = d.subject_id 
    AND a.hadm_id = SAFE_CAST(d.hadm_id AS INT64)
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 67 AND 77
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    -- T2DM: ICD-10 E11.*, ICD-9 250.4x
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = a.subject_id 
        AND a.hadm_id = SAFE_CAST(d2.hadm_id AS INT64)
        AND ((d2.icd_version = '10' AND d2.icd_code LIKE 'E11%') 
             OR (d2.icd_version = '9' AND d2.icd_code LIKE '250.4%'))
    )
    -- HF: ICD-10 I50.*, ICD-9 428.*
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
      WHERE d3.subject_id = a.subject_id 
        AND a.hadm_id = SAFE_CAST(d3.hadm_id AS INT64)
        AND ((d3.icd_version = '10' AND d3.icd_code LIKE 'I50%') 
             OR (d3.icd_version = '9' AND d3.icd_code LIKE '428%'))
    )
),

time_windows AS (
  -- Define windows per admission
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    admittime AS first_12h_start,
    TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) AS first_12h_end,
    TIMESTAMP_ADD(dischtime, INTERVAL -48 HOUR) AS final_48h_start,
    dischtime AS final_48h_end,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS los_hours
  FROM cohort
),

prescriptions_mapped AS (
  -- Map prescriptions to classes and flag initiations (new starts only)
  WITH ordered_prescriptions AS (
    SELECT 
      c.hadm_id,
      c.admittime,
      c.dischtime,
      pr.starttime,
      -- Class mapping via CASE (keyword match on drug name)
      CASE 
        WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
        WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%metform%' THEN 'met'
        WHEN LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' 
             OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%tolbutamide%' 
             OR LOWER(pr.drug) LIKE '%chlorpropamide%' THEN 'SU'
        WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' 
             OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' 
             OR LOWER(pr.drug) LIKE '%januvia%' OR LOWER(pr.drug) LIKE '%onglyza%' THEN 'DPP-4'
        WHEN LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' 
             OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' 
             OR LOWER(pr.drug) LIKE '%farxiga%' OR LOWER(pr.drug) LIKE '%jardiance%' THEN 'SGLT2'
        WHEN LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' 
             OR LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' 
             OR LOWER(pr.drug) LIKE '%albiglutide%' OR LOWER(pr.drug) LIKE '%victoza%' 
             OR LOWER(pr.drug) LIKE '%bydureon%' OR LOWER(pr.drug) LIKE '%trulicity%' 
             OR LOWER(pr.drug) LIKE '%ozempic%' THEN 'GLP-1'
        WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' 
             OR LOWER(pr.drug) LIKE '%actos%' OR LOWER(pr.drug) LIKE '%avandia%' THEN 'TZD'
        ELSE NULL
      END AS drug_class,
      -- Flag if this is an initiation (no prior order of same class in admission)
      CASE 
        WHEN LAG(drug_class) OVER (PARTITION BY pr.hadm_id, drug_class ORDER BY pr.starttime) IS NULL 
             AND drug_class IS NOT NULL THEN 1 
        ELSE 0 
      END AS is_initiation
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.subject_id = pr.subject_id 
      AND c.hadm_id = SAFE_CAST(pr.hadm_id AS INT64)
    WHERE pr.starttime IS NOT NULL
      AND pr.drug IS NOT NULL
      AND pr.drug != ''
  )
  SELECT * FROM ordered_prescriptions WHERE drug_class IS NOT NULL AND is_initiation = 1
),

initiations AS (
  -- Flag initiations per hadm_id, class, window (only for mapped classes)
  SELECT 
    tw.hadm_id,
    pm.drug_class,
    -- First 12h initiation
    CASE 
      WHEN pm.starttime >= tw.first_12h_start 
           AND pm.starttime < tw.first_12h_end 
      THEN 1 ELSE 0 
    END AS initiated_first_12h,
    -- Final 48h initiation
    CASE 
      WHEN pm.starttime >= tw.final_48h_start 
           AND pm.starttime < tw.final_48h_end 
      THEN 1 ELSE 0 
    END AS initiated_final_48h
  FROM time_windows tw
  LEFT JOIN prescriptions_mapped pm 
    ON tw.hadm_id = pm.hadm_id 
    AND pm.drug_class IS NOT NULL  -- Only join mapped rows
)

-- Aggregate percentages
SELECT 
  drug_class AS class,
  ROUND(AVG(CASE WHEN initiated_first_12h = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS first_12h_pct,
  ROUND(AVG(CASE WHEN initiated_final_48h = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS final_48h_pct,
  ROUND(AVG(CASE WHEN initiated_final_48h = 1 THEN 1.0 ELSE 0 END) * 100 - 
        AVG(CASE WHEN initiated_first_12h = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS net_change_pp
FROM (
  -- Per hadm_id, class: max initiation flag (1 if any order in window); filter LOS >=48h
  SELECT 
    i.hadm_id,
    i.drug_class,
    MAX(i.initiated_first_12h) AS initiated_first_12h,
    MAX(i.initiated_final_48h) AS initiated_final_48h
  FROM initiations i
  INNER JOIN time_windows tw ON i.hadm_id = tw.hadm_id
  WHERE i.drug_class IS NOT NULL
    AND tw.los_hours >= 48
  GROUP BY i.hadm_id, i.drug_class
) agg_per_adm
GROUP BY drug_class
ORDER BY 
  CASE drug_class
    WHEN 'insulin' THEN 1
    WHEN 'met' THEN 2
    WHEN 'SU' THEN 3
    WHEN 'DPP-4' THEN 4
    WHEN 'SGLT2' THEN 5
    WHEN 'GLP-1' THEN 6
    WHEN 'TZD' THEN 7
  END;