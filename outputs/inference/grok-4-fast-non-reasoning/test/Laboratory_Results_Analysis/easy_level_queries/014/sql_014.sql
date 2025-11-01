WITH gi_bleed_admissions AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.subject_id = diag.subject_id AND ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 49
    AND diag.seq_num = 1
    AND (
      diag.icd_code LIKE 'K92.0%' OR 
      diag.icd_code = 'I85.01' OR 
      REGEXP_CONTAINS(icd.long_title, r'(?i)gastrointestinal hemorrhage|GI bleed')
    )
),
discharge_hgb AS (
  SELECT 
    gba.hadm_id,
    le.valuenum AS hgb_g_per_dl
  FROM gi_bleed_admissions gba
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gba.subject_id = le.subject_id 
    AND gba.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE le.itemid = 50811  -- Hemoglobin
    AND le.valueuom = 'g/dL'
    AND le.valuenum IS NOT NULL 
    AND le.valuenum > 0
    AND le.charttime >= gba.admittime
    AND le.charttime <= gba.dischtime
    AND DATE(le.charttime) = DATE(gba.dischtime)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY gba.hadm_id ORDER BY le.charttime DESC) = 1
)
SELECT 
  PERCENTILE_CONT(hgb_g_per_dl, 0.75) IGNORE NULLS AS p75_discharge_hgb_g_per_dl,
  COUNT(*) AS num_qualifying_admissions
FROM discharge_hgb;