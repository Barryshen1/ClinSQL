WITH base_population AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Determine ICU status
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status,
    -- Calculate hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 82 AND 92
),

surgical_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    -- ICD-10-PCS procedure codes (0 = Medical and Surgical)
    (icd_version = 10 AND SUBSTR(icd_code, 1, 1) = '0')
    OR
    -- ICD-9-CM procedure codes (00-86 = surgery)
    (icd_version = 9 AND SAFE_CAST(SUBSTR(icd_code, 1, 2) AS INT64) BETWEEN 0 AND 86)
),

complication_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    -- ICD-10 complication codes (T80-T88)
    (icd_version = 10 AND 
     (icd_code LIKE 'T80%' OR icd_code LIKE 'T81%' OR icd_code LIKE 'T82%' OR 
      icd_code LIKE 'T83%' OR icd_code LIKE 'T84%' OR icd_code LIKE 'T85%' OR 
      icd_code LIKE 'T86%' OR icd_code LIKE 'T87%' OR icd_code LIKE 'T88%'))
    OR
    -- ICD-9 complication codes (996-999)
    (icd_version = 9 AND 
     SAFE_CAST(SUBSTR(icd_code, 1, 3) AS INT64) BETWEEN 996 AND 999)
),

comorbidity_count AS (
  SELECT
    d.hadm_id,
    COUNT(DISTINCT c.condition_name) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN (
    -- Simplified Elixhauser conditions mapping
    SELECT 'congestive_heart_failure' AS condition_name, 'I50' AS icd_prefix, 10 AS icd_version UNION ALL
    SELECT 'cardiac_arrhythmias', 'I49', 10 UNION ALL
    SELECT 'valvular_disease', 'I34', 10 UNION ALL
    SELECT 'pulmonary_circulation', 'I26', 10 UNION ALL
    SELECT 'peripheral_vascular', 'I73', 10 UNION ALL
    SELECT 'hypertension', 'I10', 10 UNION ALL
    SELECT 'paralysis', 'G83', 10 UNION ALL
    SELECT 'other_neurological', 'G20', 10 UNION ALL
    SELECT 'chronic_pulmonary', 'J44', 10 UNION ALL
    SELECT 'diabetes_uncomplicated', 'E11', 10 UNION ALL
    SELECT 'diabetes_complicated', 'E13', 10 UNION ALL
    SELECT 'hypothyroidism', 'E03', 10 UNION ALL
    SELECT 'renal_failure', 'N18', 10 UNION ALL
    SELECT 'liver_disease', 'I86', 10 UNION ALL
    SELECT 'peptic_ulcer', 'K27', 10 UNION ALL
    SELECT 'aids', 'B20', 10 UNION ALL
    SELECT 'lymphoma', 'C83', 10 UNION ALL
    SELECT 'metastatic_cancer', 'C79', 10 UNION ALL
    SELECT 'solid_tumor', 'C61', 10 UNION ALL
    SELECT 'rheumatoid_arthritis', 'M06', 10 UNION ALL
    SELECT 'coagulopathy', 'D68', 10 UNION ALL
    SELECT 'obesity', 'E66', 10 UNION ALL
    SELECT 'weight_loss', 'R63', 10 UNION ALL
    SELECT 'fluid_electrolyte', 'E87', 10 UNION ALL
    SELECT 'blood_loss_anemia', 'D50', 10 UNION ALL
    SELECT 'deficiency_anemias', 'D51', 10 UNION ALL
    SELECT 'alcohol_abuse', 'F10', 10 UNION ALL
    SELECT 'drug_abuse', 'F11', 10 UNION ALL
    SELECT 'psychoses', 'F20', 10 UNION ALL
    SELECT 'depression', 'F32', 10
  ) c ON d.icd_code LIKE CONCAT(c.icd_prefix, '%') AND d.icd_version = c.icd_version
  GROUP BY d.hadm_id
)

SELECT
  bp.icu_status,
  CASE WHEN bp.los_days <= 5 THEN '≤5' ELSE '>5' END AS los_bin,
  CASE 
    WHEN COALESCE(cc.comorbidity_count, 0) <= 1 THEN '0-1'
    WHEN cc.comorbidity_count = 2 THEN '2'
    ELSE '≥3'
  END AS comorbidity_bin,
  COUNT(*) AS N,
  AVG(bp.hospital_expire_flag) * 100 AS mortality_rate,
  AVG(COALESCE(cc.comorbidity_count, 0)) AS avg_comorbidity_count
FROM base_population bp
INNER JOIN surgical_admissions sa ON bp.hadm_id = sa.hadm_id
INNER JOIN complication_admissions ca ON bp.hadm_id = ca.hadm_id
LEFT JOIN comorbidity_count cc ON bp.hadm_id = cc.hadm_id
GROUP BY icu_status, los_bin, comorbidity_bin
ORDER BY icu_status, los_bin, comorbidity_bin;