WITH diag AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    LOWER(COALESCE(dd.long_title, '')) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
),
-- For each hadm compute flags for postoperative complications and Charlson components
hadm_diag_flags AS (
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN long_title LIKE '%postoperative%' OR long_title LIKE '%post-op%' OR long_title LIKE '%post operative%' THEN 1
        WHEN icd_version = 9 AND icd_code LIKE '998%' THEN 1
        WHEN icd_version = 10 AND icd_code LIKE 'T81%' THEN 1
        ELSE 0
      END
    ) AS postop_flag,

    -- Charlson components (keyword-based, approximate)
    MAX(CASE WHEN long_title LIKE '%myocardial infarction%' OR long_title LIKE '%myocardial%infarct%' OR long_title LIKE '%mi%' THEN 1 ELSE 0 END) AS char_mi,
    MAX(CASE WHEN long_title LIKE '%congestive heart failure%' OR long_title LIKE '%heart failure%' OR long_title LIKE '%cardiac failure%' THEN 1 ELSE 0 END) AS char_chf,
    MAX(CASE WHEN long_title LIKE '%peripheral vascular%' OR long_title LIKE '%peripheral arterial%' OR long_title LIKE '%pvd%' THEN 1 ELSE 0 END) AS char_pvd,
    MAX(CASE WHEN long_title LIKE '%cerebrovascular%' OR long_title LIKE '%cva%' OR long_title LIKE '%stroke%' THEN 1 ELSE 0 END) AS char_cva,
    MAX(CASE WHEN long_title LIKE '%dement%' THEN 1 ELSE 0 END) AS char_dementia,
    MAX(CASE WHEN long_title LIKE '%chronic obstructive%' OR long_title LIKE '%copd%' OR long_title LIKE '%chronic pulmonary%' OR long_title LIKE '%pulmonary disease%' THEN 1 ELSE 0 END) AS char_copd,
    MAX(CASE WHEN long_title LIKE '%rheumat%' OR long_title LIKE '%rheumatoid%' THEN 1 ELSE 0 END) AS char_rheum,
    MAX(CASE WHEN long_title LIKE '%peptic ulcer%' OR long_title LIKE '%ulcer%' THEN 1 ELSE 0 END) AS char_pud,
    MAX(CASE WHEN long_title LIKE '%mild liver%' OR long_title LIKE '%chronic liver%' OR long_title LIKE '%fatty liver%' THEN 1 ELSE 0 END) AS char_mild_liver,
    MAX(CASE WHEN long_title LIKE '%diabetes%' AND (long_title LIKE '%complic%' OR long_title LIKE '%with%complication%' OR long_title LIKE '%with complications%') THEN 1 ELSE 0 END) AS char_dm_complic,
    MAX(CASE WHEN long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS char_dm,
    MAX(CASE WHEN long_title LIKE '%hemiplegia%' OR long_title LIKE '%paraplegia%' OR long_title LIKE '%paralysis%' THEN 1 ELSE 0 END) AS char_hemi,
    MAX(CASE WHEN long_title LIKE '%renal%' OR long_title LIKE '%kidney%' OR long_title LIKE '%chronic kidney%' OR long_title LIKE '%crf%' THEN 1 ELSE 0 END) AS char_renal,
    MAX(CASE WHEN (long_title LIKE '%malign%' OR long_title LIKE '%neoplasm%' OR long_title LIKE '%carcinoma%') AND long_title NOT LIKE '%metastat%' THEN 1 ELSE 0 END) AS char_malignancy,
    MAX(CASE WHEN long_title LIKE '%metastat%' OR long_title LIKE '%metastatic%' OR long_title LIKE '%secondary malignant%' THEN 1 ELSE 0 END) AS char_metastatic,
    MAX(CASE WHEN long_title LIKE '%hiv%' OR long_title LIKE '%aids%' THEN 1 ELSE 0 END) AS char_hiv
  FROM diag
  GROUP BY hadm_id
),
-- Build admissions cohort with patient filters and join diag flags
admissions_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- LOS in days (1-based)
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 AS los_days,
    -- ICU flag: exists an ICU stay for this hadm_id
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS location_type,
    -- diag flags
    COALESCE(h.postop_flag, 0) AS postop_flag,
    -- compute Charlson score (approx)
    -- weights: mi 1, chf 1, pvd 1, cva 1, dementia 1, copd 1, rheum 1, pud 1, mild liver 1,
    -- dm uncomplicated 1, dm with comp 2, hemi 2, renal 2, malignancy 2, metastatic 6, hiv 6
    COALESCE(h.char_mi,0) AS char_mi,
    COALESCE(h.char_chf,0) AS char_chf,
    COALESCE(h.char_pvd,0) AS char_pvd,
    COALESCE(h.char_cva,0) AS char_cva,
    COALESCE(h.char_dementia,0) AS char_dementia,
    COALESCE(h.char_copd,0) AS char_copd,
    COALESCE(h.char_rheum,0) AS char_rheum,
    COALESCE(h.char_pud,0) AS char_pud,
    COALESCE(h.char_mild_liver,0) AS char_mild_liver,
    COALESCE(h.char_dm,0) AS char_dm,
    COALESCE(h.char_dm_complic,0) AS char_dm_complic,
    COALESCE(h.char_hemi,0) AS char_hemi,
    COALESCE(h.char_renal,0) AS char_renal,
    COALESCE(h.char_malignancy,0) AS char_malignancy,
    COALESCE(h.char_metastatic,0) AS char_metastatic,
    COALESCE(h.char_hiv,0) AS char_hiv
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN hadm_diag_flags h
      ON a.hadm_id = h.hadm_id
    LEFT JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) icu
      ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    -- only admissions that had a postoperative-complication code/description
    AND COALESCE(h.postop_flag,0) = 1
),
-- Finalize charlson score and bins, compute death/time-to-death
admissions_final AS (
  SELECT
    subject_id,
    hadm_id,
    location_type,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag AS hospital_death,
    los_days,
    -- LOS bin
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_bin,
    -- Charlson score calculation with precedence rules
    (
      -- 1-point conditions
      (char_mi * 1) +
      (char_chf * 1) +
      (char_pvd * 1) +
      (char_cva * 1) +
      (char_dementia * 1) +
      (char_copd * 1) +
      (char_rheum * 1) +
      (char_pud * 1) +
      (char_mild_liver * 1) +
      -- diabetes: complicated -> 2, else uncomplicated -> 1
      (CASE WHEN char_dm_complic = 1 THEN 2 WHEN char_dm = 1 THEN 1 ELSE 0 END) +
      -- hemiplegia/paralysis -> 2
      (char_hemi * 2) +
      -- renal -> 2
      (char_renal * 2) +
      -- malignancy vs metastatic: metastatic takes precedence
      (CASE WHEN char_metastatic = 1 THEN 6 WHEN char_malignancy = 1 THEN 2 ELSE 0 END) +
      -- hiv/aids
      (char_hiv * 6)
    ) AS charlson_score,
    -- charlson bin
    CASE
      WHEN (
        (char_mi * 1) +
        (char_chf * 1) +
        (char_pvd * 1) +
        (char_cva * 1) +
        (char_dementia * 1) +
        (char_copd * 1) +
        (char_rheum * 1) +
        (char_pud * 1) +
        (char_mild_liver * 1) +
        (CASE WHEN char_dm_complic = 1 THEN 2 WHEN char_dm = 1 THEN 1 ELSE 0 END) +
        (char_hemi * 2) +
        (char_renal * 2) +
        (CASE WHEN char_metastatic = 1 THEN 6 WHEN char_malignancy = 1 THEN 2 ELSE 0 END) +
        (char_hiv * 6)
      ) <= 3 THEN '≤3'
      WHEN (
        (char_mi * 1) +
        (char_chf * 1) +
        (char_pvd * 1) +
        (char_cva * 1) +
        (char_dementia * 1) +
        (char_copd * 1) +
        (char_rheum * 1) +
        (char_pud * 1) +
        (char_mild_liver * 1) +
        (CASE WHEN char_dm_complic = 1 THEN 2 WHEN char_dm = 1 THEN 1 ELSE 0 END) +
        (char_hemi * 2) +
        (char_renal * 2) +
        (CASE WHEN char_metastatic = 1 THEN 6 WHEN char_malignancy = 1 THEN 2 ELSE 0 END) +
        (char_hiv * 6)
      ) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_bin,
    -- time-to-death in days (fractional). NULL if no in-hospital death or missing deathtime.
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL THEN
        TIMESTAMP_DIFF(deathtime, admittime, MINUTE) / 1440.0
      ELSE NULL
    END AS time_to_death_days
  FROM admissions_cohort
)
-- Two result sets combined:
-- 1) Stratified by ICU vs Non-ICU and LOS bins
-- 2) Stratified by ICU vs Non-ICU and Charlson bins
SELECT
  'By LOS' AS stratification,
  location_type,
  los_bin AS subgroup,
  COUNT(*) AS N,
  SUM(CAST(hospital_death AS INT64)) AS deaths,
  ROUND(100.0 * SUM(CAST(hospital_death AS INT64)) / COUNT(*), 2) AS mortality_pct,
  -- median time-to-death among decedents (approx)
  APPROX_QUANTILES(IF(hospital_death = 1, time_to_death_days, NULL), 2)[OFFSET(1)] AS median_time_to_death_days
FROM admissions_final
GROUP BY location_type, los_bin

UNION ALL

SELECT
  'By Charlson' AS stratification,
  location_type,
  charlson_bin AS subgroup,
  COUNT(*) AS N,
  SUM(CAST(hospital_death AS INT64)) AS deaths,
  ROUND(100.0 * SUM(CAST(hospital_death AS INT64)) / COUNT(*), 2) AS mortality_pct,
  APPROX_QUANTILES(IF(hospital_death = 1, time_to_death_days, NULL), 2)[OFFSET(1)] AS median_time_to_death_days
FROM admissions_final
GROUP BY location_type, charlson_bin
ORDER BY stratification, location_type, subgroup;