WITH elixhauser_categories AS (
  -- Simplified Elixhauser ICD-10 codes (common set; based on standard MIMIC-IV mappings)
  SELECT 'Elixhauser' AS category, icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE CAST(icd_version AS STRING) = '10'
    AND icd_code IN (
      -- Congestive heart failure
      'I09.9', 'I11.0', 'I13.0', 'I13.2', 'I25.5', 'I42.0', 'I42.5', 'I42.6', 'I42.7', 'I42.8', 'I42.9', 'I43.0', 'I43.1', 'I43.2', 'I50.1', 'I50.9',
      -- Cardiac arrhythmias
      'I44.1', 'I44.2', 'I44.3', 'I45.5', 'I45.6', 'I45.9', 'I47.0', 'I47.1', 'I47.2', 'I47.9', 'I48.0', 'I48.1', 'I48.2', 'I48.9', 'I49.0', 'I49.1', 'I49.2', 'I49.3', 'I49.4', 'I49.5', 'I49.8', 'I49.9', 'R00.0', 'R00.1', 'T82.1', 'T82.7',
      -- Valvular heart disease (subset)
      'A18.84', 'I05.0', 'I05.1', 'I05.2', 'I05.8', 'I05.9', 'I06.0', 'I06.1', 'I06.2', 'I06.8', 'I06.9', 'I07.0', 'I07.1', 'I07.2', 'I07.8', 'I07.9', 'I08.0', 'I08.1', 'I08.3', 'I09.1', 'I09.8', 'I34.0', 'I34.1', 'I34.2', 'I34.8', 'I34.9', 'I35.0', 'I35.1', 'I35.2', 'I35.8', 'I35.9', 'I36.0', 'I36.1', 'I36.2', 'I36.8', 'I36.9', 'I37.0', 'I37.1', 'I37.2', 'I37.8', 'I37.9', 'I38.0', 'I38.3', 'I38.8', 'I39.0', 'I39.1', 'I39.2', 'I39.3', 'I39.4', 'I39.8', 'I39.9', 'Q23.0', 'Q23.1', 'Q23.2', 'Q23.3', 'Q23.4', 'Q23.8', 'Q23.9', 'Z95.2', 'Z95.3', 'Z95.4',
      -- Pulmonary circulation
      'I26.0', 'I26.9', 'I27.0', 'I27.2', 'I27.8', 'I27.9', 'I28.0', 'I28.1', 'I28.8', 'I28.9',
      -- Peripheral vascular
      'I70.0', 'I70.2', 'I70.3', 'I70.4', 'I70.5', 'I70.6', 'I70.7', 'I70.8', 'I70.9', 'I71.4', 'I71.8', 'I71.9', 'I72.4', 'I73.1', 'I73.8', 'I73.9', 'I77.1', 'I79.0', 'K55.1', 'K55.8', 'K95.8', 'Z95.9',
      -- Hypertension uncomplicated/complicated (subset)
      'I10', 'I11.9', 'I12.9', 'I13.1', 'I13.9', 'I15.0', 'I15.1', 'I15.2', 'I15.8', 'I15.9', 'I16.0', 'I16.1', 'I16.9',
      -- Paralysis
      'G81.0', 'G81.9', 'G82.0', 'G82.1', 'G82.2', 'G82.3', 'G82.4', 'G82.5', 'G82.8', 'G82.9', 'G83.0', 'G83.1', 'G83.2', 'G83.3', 'G83.4', 'G83.8', 'G83.9',
      -- Other neurological
      'G93.4', 'R47.0', 'R47.1', 'R56.0', 'R56.1', 'R56.8', 'R56.9',
      -- Chronic pulmonary
      'I27.8', 'J40', 'J41.0', 'J41.1', 'J41.8', 'J42', 'J43.0', 'J43.1', 'J43.2', 'J43.8', 'J43.9', 'J44.0', 'J44.1', 'J44.9', 'J45.2', 'J45.4', 'J45.5', 'J45.6', 'J45.7', 'J45.8', 'J45.9', 'J47.0', 'J47.1', 'J47.2', 'J60', 'J67.0', 'J67.1', 'J67.2', 'J67.8', 'J67.9', 'J68.4', 'J68.8', 'J70.1', 'M05.3',
      -- Diabetes uncomplicated/complicated
      'E10.0', 'E10.1', 'E10.2', 'E10.3', 'E10.8', 'E10.9', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.8', 'E11.9', 'E12.0', 'E12.1', 'E12.2', 'E12.3', 'E12.8', 'E12.9', 'E13.0', 'E13.1', 'E13.2', 'E13.3', 'E13.8', 'E13.9', 'E14.0', 'E14.1', 'E14.2', 'E14.3', 'E14.8', 'E14.9',
      -- Hypothyroidism
      'E00.0', 'E00.1', 'E00.2', 'E00.8', 'E00.9', 'E01.0', 'E01.1', 'E01.2', 'E01.8', 'E01.9', 'E02', 'E03.0', 'E03.1', 'E03.2', 'E03.8', 'E03.9', 'E89.0',
      -- Renal failure
      'I12.0', 'I13.0', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N19', 'N25.0', 'Z49.0', 'Z49.1', 'Z49.2', 'Z94.0', 'Z99.2',
      -- Liver disease
      'B18.0', 'B18.1', 'B18.2', 'I85.0', 'I85.1', 'I85.8', 'I85.9', 'I86.4', 'I98.2', 'K70.0', 'K70.3', 'K70.9', 'K71.1', 'K71.3', 'K71.4', 'K71.5', 'K71.7', 'K73', 'K74.3', 'K74.4', 'K74.5', 'K74.6', 'K76.0', 'K76.3', 'K76.4', 'K76.8', 'K76.9', 'Z94.4',
      -- Peptic ulcer
      'K25.0', 'K25.1', 'K25.2', 'K25.3', 'K25.4', 'K25.5', 'K25.6', 'K25.7', 'K25.9', 'K26.0', 'K26.1', 'K26.2', 'K26.3', 'K26.4', 'K26.5', 'K26.6', 'K26.7', 'K26.9', 'K27.0', 'K27.1', 'K27.2', 'K27.3', 'K27.4', 'K27.5', 'K27.6', 'K27.7', 'K27.9', 'K28.0', 'K28.1', 'K28.2', 'K28.3', 'K28.4', 'K28.5', 'K28.6', 'K28.7', 'K28.9',
      -- AIDS
      'B20', 'B21', 'B22', 'B24',
      -- Lymphoma
      'C81', 'C82', 'C83', 'C84', 'C85', 'C88', 'C96',
      -- Metastatic cancer
      'C77', 'C78', 'C79', 'C80',
      -- Solid tumor
      'C00', 'C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08', 'C09', 'C10', 'C11', 'C12', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'C19', 'C20', 'C21', 'C22', 'C23', 'C24', 'C25', 'C26', 'C30', 'C31', 'C32', 'C33', 'C34', 'C37', 'C38', 'C39', 'C40', 'C41', 'C43', 'C45', 'C46', 'C47', 'C48', 'C49', 'C50', 'C53', 'C54', 'C55', 'C56', 'C57', 'C58', 'C60', 'C61', 'C62', 'C64', 'C65', 'C66', 'C67', 'C68', 'C69', 'C70', 'C71', 'C72', 'C73', 'C74', 'C75', 'C76',
      -- Rheumatoid arthritis
      'M05.0', 'M05.1', 'M05.3', 'M06.0', 'M06.8', 'M06.9',
      -- Coagulopathy
      'D65', 'D66', 'D67', 'D68', 'D69.1', 'D69.3', 'D69.4', 'D69.5', 'D69.6',
      -- Obesity
      'E66.0', 'E66.1', 'E66.2', 'E66.8', 'E66.9', 'Z68.3', 'Z68.4',
      -- Weight loss
      'E40', 'E41', 'E42', 'E43', 'E44', 'E45', 'E46', 'R63.4', 'R64',
      -- Fluid/electrolyte
      'E22.2', 'E86', 'E87',
      -- Blood loss anemia
      'D50.0',
      -- Deficiency anemia
      'D50.8', 'D50.9', 'D51.0', 'D51.1', 'D51.2', 'D51.8', 'D51.9', 'D52.0', 'D52.1', 'D52.8', 'D52.9', 'D53.0', 'D53.1', 'D53.2', 'D53.8', 'D53.9',
      -- Alcohol abuse
      'F10.1', 'F10.2', 'E52', 'G62.1', 'I42.6', 'K29.2', 'K70.0', 'K70.3', 'P43.2', 'T51', 'Z71.4',
      -- Drug abuse
      'F11.1', 'F11.2', 'F12.1', 'F12.2', 'F13.1', 'F13.2', 'F14.1', 'F14.2', 'F15.1', 'F15.2', 'F16.1', 'F16.2', 'F18.1', 'F18.2', 'F19.1', 'F19.2', 'Z71.5',
      -- Psychoses
      'F20', 'F22', 'F23', 'F24', 'F25', 'F28', 'F29', 'F30.2', 'F31.2', 'F31.5',
      -- Depression
      'F20.4', 'F31.3', 'F31.4', 'F31.5', 'F32', 'F33'
    )
),
comorb_counts AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT ec.icd_code) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN elixhauser_categories ec 
    ON di.icd_code = ec.icd_code
  WHERE CAST(di.icd_version AS STRING) = '10' AND di.seq_num >= 2  -- Secondary diagnoses
  GROUP BY subject_id, hadm_id
),
postop_complications AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE CAST(d.icd_version AS STRING) = '10' AND d.icd_code LIKE 'T81%'
),
icu_flags AS (
  SELECT 
    t.subject_id,
    t.hadm_id,
    MAX(CASE WHEN LOWER(t.careunit) LIKE '%icu%' THEN 1 ELSE 0 END) AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
  GROUP BY subject_id, hadm_id
),
icu_los AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    -- Take first ICU stay LOS as proxy (or AVG if multiple)
    AVG(TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) / 24.0) AS icu_los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  GROUP BY subject_id, hadm_id
),
filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS hosp_los_days,
    COALESCE(cc.comorb_count, 0) AS comorb_count,
    COALESCE(icu.icu_flag, 0) AS icu_flag,
    CASE WHEN COALESCE(icu.icu_flag, 0) = 1 THEN il.icu_los_days ELSE NULL END AS icu_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN postop_complications pc ON a.subject_id = pc.subject_id AND a.hadm_id = pc.hadm_id
  LEFT JOIN comorb_counts cc ON a.subject_id = cc.subject_id AND a.hadm_id = cc.hadm_id
  LEFT JOIN icu_flags icu ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  LEFT JOIN icu_los il ON a.subject_id = il.subject_id AND a.hadm_id = il.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND a.dischtime IS NOT NULL
)
SELECT 
  icu_group,
  los_group,
  comorb_group,
  COUNT(DISTINCT hadm_id) AS N,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * 100, 2) AS mortality_pct,
  ROUND(AVG(comorb_count), 2) AS avg_comorb_count
FROM (
  SELECT *,
    CASE WHEN icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    CASE WHEN hosp_los_days <= 5 THEN '≤5' ELSE '>5' END AS los_group,
    CASE 
      WHEN comorb_count <= 1 THEN '0-1'
      WHEN comorb_count = 2 THEN '2'
      ELSE '≥3'
    END AS comorb_group
  FROM filtered_admissions
)
GROUP BY icu_group, los_group, comorb_group
ORDER BY icu_group, los_group, comorb_group;