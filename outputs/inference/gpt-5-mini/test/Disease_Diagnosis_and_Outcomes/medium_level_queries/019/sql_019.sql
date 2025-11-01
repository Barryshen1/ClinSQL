with a heart-failure diagnosis
WITH hf_adms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- identify heart failure by diagnosis description (case-insensitive)
    AND (
      LOWER(COALESCE(di.long_title, '')) LIKE '%heart failure%'
      OR LOWER(COALESCE(d.icd_code, '')) LIKE 'i50%'  -- ICD-10 heart failure codes
      OR LOWER(COALESCE(d.icd_code, '')) LIKE '428%' -- ICD-9 heart failure codes
    )
),

-- Aggregate diagnoses for each admission to derive Charlson components (keyword-based approximation)
diag_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%myocardial%' THEN 1 ELSE 0 END) AS fh_mi,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS fh_chf,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%peripheral vascular%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%peripheral artery%' THEN 1 ELSE 0 END) AS fh_pvd,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%cerebrovascular%'
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%stroke%'
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%transient ischemic attack%' THEN 1 ELSE 0 END) AS fh_cvd,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%dementia%' THEN 1 ELSE 0 END) AS fh_dementia,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%chronic obstructive pulmonary%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%emphysema%'
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%chronic bronchitis%'
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%copd%' THEN 1 ELSE 0 END) AS fh_copd,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%rheumatoid%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%connective tissue%' THEN 1 ELSE 0 END) AS fh_connective,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%peptic ulcer%' THEN 1 ELSE 0 END) AS fh_peptic,
    -- liver: moderate/severe vs mild
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%cirrhosis%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%hepatic failure%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%portal hypertension%' THEN 1 ELSE 0 END) AS fh_liver_modsev,
    MAX(CASE WHEN (LOWER(COALESCE(di.long_title, '')) LIKE '%liver disease%' 
                  OR LOWER(COALESCE(di.long_title, '')) LIKE '%chronic hepatitis%')
                 AND NOT (LOWER(COALESCE(di.long_title, '')) LIKE '%cirrhosis%'
                          OR LOWER(COALESCE(di.long_title, '')) LIKE '%hepatic failure%') THEN 1 ELSE 0 END) AS fh_liver_mild,
    -- diabetes with/without complications
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%diabet%' 
                 AND (LOWER(COALESCE(di.long_title, '')) LIKE '%with%' 
                      OR LOWER(COALESCE(di.long_title, '')) LIKE '%complic%'
                      OR LOWER(COALESCE(di.long_title, '')) LIKE '%nephropathy%'
                      OR LOWER(COALESCE(di.long_title, '')) LIKE '%retinopathy%'
                      OR LOWER(COALESCE(di.long_title, '')) LIKE '%neuropathy%'
                      OR LOWER(COALESCE(di.long_title, '')) LIKE '%ulcer%') THEN 1 ELSE 0 END) AS fh_dm_comp,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%diabet%' THEN 1 ELSE 0 END) AS fh_dm_any,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%hemipleg%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%parapleg%' THEN 1 ELSE 0 END) AS fh_hemipleg,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%renal%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%kidney%' 
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%chronic kidney%' THEN 1 ELSE 0 END) AS fh_renal,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%malignant%'
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%neoplasm%'
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%primary malignant%' THEN 1 ELSE 0 END) AS fh_malig_any,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%metastatic%'
                 OR LOWER(COALESCE(di.long_title, '')) LIKE '%secondary malignant%' THEN 1 ELSE 0 END) AS fh_malig_meta,
    MAX(CASE WHEN LOWER(COALESCE(di.long_title, '')) LIKE '%hiv%' OR LOWER(COALESCE(di.long_title, '')) LIKE '%aids%' THEN 1 ELSE 0 END) AS fh_aids
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM hf_adms)
  GROUP BY d.hadm_id
),

-- compute Charlson score (approximate, keyword-based)
charlson AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- LOS in days (count partial day as 1)
    CEIL(ABS(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE)) / 1440.0) AS los_days,
    -- compute weighted Charlson components (approximate)
    SAFE_CAST(
      COALESCE(df.fh_mi,0) * 1
    + COALESCE(df.fh_chf,0) * 1
    + COALESCE(df.fh_pvd,0) * 1
    + COALESCE(df.fh_cvd,0) * 1
    + COALESCE(df.fh_dementia,0) * 1
    + COALESCE(df.fh_copd,0) * 1
    + COALESCE(df.fh_connective,0) * 1
    + COALESCE(df.fh_peptic,0) * 1
    + -- liver: choose higher weight if moderate/severe present
      CASE WHEN COALESCE(df.fh_liver_modsev,0)=1 THEN 3 WHEN COALESCE(df.fh_liver_mild,0)=1 THEN 1 ELSE 0 END
    + -- diabetes: 2 if complicated, else 1 if any
      CASE WHEN COALESCE(df.fh_dm_comp,0)=1 THEN 2 WHEN COALESCE(df.fh_dm_any,0)=1 THEN 1 ELSE 0 END
    + COALESCE(df.fh_hemipleg,0) * 2
    + COALESCE(df.fh_renal,0) * 2
    + COALESCE(df.fh_malig_any,0) * 2
    + COALESCE(df.fh_malig_meta,0) * 6
    + COALESCE(df.fh_aids,0) * 6
    AS INT64) AS charlson_score
  FROM hf_adms a
  LEFT JOIN diag_flags df
    ON a.hadm_id = df.hadm_id
),

-- assign Charlson groups and LOS categories, and discharge destination buckets
final_prep AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE 'unknown'
    END AS los_cat,
    CASE
      WHEN charlson_score IS NULL THEN 'unknown'
      WHEN charlson_score <= 3 THEN '≤3'
      WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group,
    LOWER(COALESCE(discharge_location, '')) AS discharge_location
  FROM charlson
)

-- Aggregate results by LOS category and Charlson group
SELECT
  los_cat,
  charlson_group,
  COUNT(1) AS n_admissions,
  ROUND(100.0 * SUM(IF(hospital_expire_flag = 1, 1, 0)) / COUNT(1), 2) AS inhospital_mortality_pct,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- reference mean LOS for Charlson ≤3 within same LOS bin
  ROUND(AVG(los_days) - ref.mean_los_ref, 2) AS abs_los_diff_vs_charlson_le3,
  CASE
    WHEN ref.mean_los_ref IS NULL OR ref.mean_los_ref = 0 THEN NULL
    ELSE ROUND(100.0 * (AVG(los_days) - ref.mean_los_ref) / ref.mean_los_ref, 1)
  END AS rel_los_diff_pct_vs_charlson_le3,
  -- discharge location percentages (home / rehab / SNF / hospice)
  ROUND(100.0 * SUM(CASE WHEN discharge_location LIKE '%home%' THEN 1 ELSE 0 END) / COUNT(1), 1) AS pct_discharge_home,
  ROUND(100.0 * SUM(CASE WHEN discharge_location LIKE '%rehab%' OR discharge_location LIKE '%rehabilit%' THEN 1 ELSE 0 END) / COUNT(1), 1) AS pct_discharge_rehab,
  ROUND(100.0 * SUM(CASE WHEN discharge_location LIKE '%skilled nursing%' OR discharge_location LIKE '%snf%' OR discharge_location LIKE '%nursing home%' THEN 1 ELSE 0 END) / COUNT(1), 1) AS pct_discharge_snf,
  ROUND(100.0 * SUM(CASE WHEN discharge_location LIKE '%hospice%' THEN 1 ELSE 0 END) / COUNT(1), 1) AS pct_discharge_hospice
FROM final_prep fp
LEFT JOIN (
  -- compute reference mean LOS for Charlson ≤3 per LOS category
  SELECT
    los_cat AS r_los_cat,
    AVG(los_days) AS mean_los_ref
  FROM final_prep
  WHERE charlson_group = '≤3'
  GROUP BY los_cat
) ref
  ON fp.los_cat = ref.r_los_cat
GROUP BY los_cat, charlson_group, ref.mean_los_ref
ORDER BY
  -- order LOS bins sensibly
  CASE los_cat WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 WHEN '>=8' THEN 3 ELSE 4 END,
  CASE charlson_group WHEN '≤3' THEN 1 WHEN '4-5' THEN 2 WHEN '>5' THEN 3 ELSE 4 END;