WITH chest_pain_adms AS (
  -- Identify emergency admissions for male patients aged 61-71 with primary chest pain diagnosis (ICD-10 R07*)
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.admission_type = 'EMERGENCY'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = '10'  -- ICD-10
    AND d.icd_code LIKE 'R07%'  -- Chest pain codes
),
hs_tnt_initial AS (
  -- Get first hs-TnT value per qualifying admission
  SELECT 
    cpa.subject_id,
    cpa.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom
  FROM chest_pain_adms cpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cpa.subject_id = le.subject_id AND cpa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE li.category = 'Chemistry'
    AND li.label LIKE '%troponin%'
    AND li.label LIKE '%T%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/L'  -- Standard unit; adjust if needed
    AND le.charttime >= cpa.admittime  -- After admission
  QUALIFY ROW_NUMBER() OVER (PARTITION BY cpa.subject_id, cpa.hadm_id ORDER BY le.charttime) = 1
),
categorized_tnt AS (
  -- Categorize hs-TnT values
  SELECT 
    *,
    CASE 
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum < 52 THEN 'Borderline'
      ELSE 'Myocardial injury'
    END AS hs_tnt_category
  FROM hs_tnt_initial
)
-- Compute percent distribution
SELECT 
  hs_tnt_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized_tnt
GROUP BY hs_tnt_category
ORDER BY 
  CASE hs_tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;