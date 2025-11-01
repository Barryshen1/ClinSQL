WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.race,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
    -- require HF diagnosis on the same admission
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        (
          LOWER(COALESCE(d.long_title, '')) LIKE '%heart failure%'
          OR di.icd_code LIKE '428%'  -- ICD-9 CHF codes
          OR di.icd_code LIKE 'I50%'  -- ICD-10 heart failure
        )
    ) hf ON hf.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Charlson comorbidity flags & score per admission (approximate via text/code matching)
comorbids AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%myocardial%' OR di.icd_code LIKE '410%' OR di.icd_code LIKE 'I21%' THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%heart failure%' OR di.icd_code LIKE '428%' OR di.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%peripheral vascular%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%peripheral artery%' THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%cerebrovascular%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%stroke%' OR di.icd_code LIKE '43%' OR di.icd_code LIKE 'I6%' THEN 1 ELSE 0 END) AS cerebro,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%dement%' THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%chronic obstructive%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%copd%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%emphysema%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%chronic respiratory%' THEN 1 ELSE 0 END) AS chronic_pulm,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%rheumat%' THEN 1 ELSE 0 END) AS rheumatic,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%peptic%' THEN 1 ELSE 0 END) AS peptic_ulcer,
    -- liver: mild vs moderate/severe
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%cirrhosis%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%hepatic failure%' THEN 1 ELSE 0 END) AS liver_severe,
    MAX(CASE WHEN (LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%liver%' AND NOT (LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%cirrhosis%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%failure%')) THEN 1 ELSE 0 END) AS liver_mild,
    -- diabetes with/without complication (approximate)
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%diabetes%' AND (LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%with%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%complic%') THEN 1 ELSE 0 END) AS dm_with_comp,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS dm_any,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%hemiplegia%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%paraplegia%' THEN 1 ELSE 0 END) AS hemiplegia,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%renal failure%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%chronic kidney%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%end stage renal%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%kidney failure%' THEN 1 ELSE 0 END) AS renal_modsev,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%malignant neoplasm%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%primary malignant%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%carcinoma%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%neoplasm%' THEN 1 ELSE 0 END) AS tumor_any,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%leukemia%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%lymphoma%' THEN 1 ELSE 0 END) AS leukemia_lymphoma,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%metastatic%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%secondary malignant%' THEN 1 ELSE 0 END) AS metastatic,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%hiv%' OR LOWER(COALESCE(d.long_title, di.icd_code)) LIKE '%aids%' THEN 1 ELSE 0 END) AS aids_hiv
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.hadm_id IN (SELECT hadm_id FROM hf_admissions)
  GROUP BY
    di.hadm_id
),

-- Procedures indicating mech vent or dialysis (per admission)
proc_flags AS (
  SELECT
    pi.hadm_id,
    MAX(CASE WHEN LOWER(COALESCE(dp.long_title, pi.icd_code)) LIKE '%ventilat%' OR LOWER(COALESCE(dp.long_title, pi.icd_code)) LIKE '%intubat%' OR pi.icd_code LIKE '96.7%' OR pi.icd_code LIKE '5A19%' THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN LOWER(COALESCE(dp.long_title, pi.icd_code)) LIKE '%dialy%' OR LOWER(COALESCE(dp.long_title, pi.icd_code)) LIKE '%renal replacement%' OR LOWER(COALESCE(dp.long_title, pi.icd_code)) LIKE '%hemodialysis%' OR pi.icd_code LIKE '39.95%' THEN 1 ELSE 0 END) AS rrt
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE
    pi.hadm_id IN (SELECT hadm_id FROM hf_admissions)
  GROUP BY
    pi.hadm_id
),

-- Vasopressors: look for common vasopressor drug names in prescriptions (approximate)
med_flags AS (
  SELECT
    p.hadm_id,
    MAX(CASE WHEN LOWER(COALESCE(p.drug, '')) LIKE '%norepineph%' OR LOWER(COALESCE(p.drug, '')) LIKE '%noradrenaline%' OR LOWER(COALESCE(p.drug, '')) LIKE '%epineph%' OR LOWER(COALESCE(p.drug, '')) LIKE '%phenyleph%' OR LOWER(COALESCE(p.drug, '')) LIKE '%vasopressin%' OR LOWER(COALESCE(p.drug, '')) LIKE '%dopamine%' OR LOWER(COALESCE(p.drug, '')) LIKE '%dobutamin%' OR LOWER(COALESCE(p.drug, '')) LIKE '%metaraminol%' OR LOWER(COALESCE(p.drug, '')) LIKE '%ephedrine%' THEN 1 ELSE 0 END) AS vasopressor
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    p.hadm_id IN (SELECT hadm_id FROM hf_admissions)
  GROUP BY
    p.hadm_id
),

-- ICU flag per admission
icu_flag AS (
  SELECT
    hadm_id,
    1 AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE hadm_id IN (SELECT hadm_id FROM hf_admissions)
  GROUP BY hadm_id
),

-- Combine all per-admission data
admission_features AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    h.los_days,
    CASE WHEN h.los_days <= 7 THEN '<=7' ELSE '>7' END AS los_cat,
    IFNULL(i.icu_flag, 0) AS icu_flag,
    -- comorbids flags (default 0)
    COALESCE(c.mi, 0) AS mi,
    COALESCE(c.chf, 0) AS chf,
    COALESCE(c.pvd, 0) AS pvd,
    COALESCE(c.cerebro, 0) AS cerebro,
    COALESCE(c.dementia, 0) AS dementia,
    COALESCE(c.chronic_pulm, 0) AS chronic_pulm,
    COALESCE(c.rheumatic, 0) AS rheumatic,
    COALESCE(c.peptic_ulcer, 0) AS peptic_ulcer,
    COALESCE(c.liver_mild, 0) AS liver_mild,
    COALESCE(c.liver_severe, 0) AS liver_severe,
    COALESCE(c.dm_with_comp, 0) AS dm_with_comp,
    COALESCE(c.dm_any, 0) AS dm_any,
    COALESCE(c.hemiplegia, 0) AS hemiplegia,
    COALESCE(c.renal_modsev, 0) AS renal_modsev,
    COALESCE(c.tumor_any, 0) AS tumor_any,
    COALESCE(c.leukemia_lymphoma, 0) AS leukemia_lymphoma,
    COALESCE(c.metastatic, 0) AS metastatic,
    COALESCE(c.aids_hiv, 0) AS aids_hiv,
    -- procedures/meds
    COALESCE(pf.mech_vent, 0) AS mech_vent,
    COALESCE(pf.rrt, 0) AS rrt,
    COALESCE(mf.vasopressor, 0) AS vasopressor
  FROM
    hf_admissions h
    LEFT JOIN comorbids c USING (hadm_id)
    LEFT JOIN proc_flags pf USING (hadm_id)
    LEFT JOIN med_flags mf USING (hadm_id)
    LEFT JOIN icu_flag i USING (hadm_id)
),

-- Compute Charlson score (approximate) and categorize
admission_with_charlson AS (
  SELECT
    *,
    -- Charlson weights applied (approximate based on flags above)
    (
      -- 1-point conditions
      COALESCE(mi,0) * 1
      + COALESCE(chf,0) * 1
      + COALESCE(pvd,0) * 1
      + COALESCE(cerebro,0) * 1
      + COALESCE(dementia,0) * 1
      + COALESCE(chronic_pulm,0) * 1
      + COALESCE(rheumatic,0) * 1
      + COALESCE(peptic_ulcer,0) * 1
      + COALESCE(liver_mild,0) * 1
      -- diabetes: either 1 or 2
      + CASE WHEN COALESCE(dm_with_comp,0) = 1 THEN 2 WHEN COALESCE(dm_any,0) = 1 THEN 1 ELSE 0 END
      -- 2-point conditions
      + COALESCE(hemiplegia,0) * 2
      + COALESCE(renal_modsev,0) * 2
      + COALESCE(leukemia_lymphoma,0) * 2
      -- tumors: 2 unless metastatic (6)
      + CASE WHEN COALESCE(metastatic,0) = 1 THEN 6 WHEN COALESCE(tumor_any,0) = 1 THEN 2 ELSE 0 END
      -- liver severe
      + COALESCE(liver_severe,0) * 3
      -- AIDS
      + COALESCE(aids_hiv,0) * 6
    ) AS charlson_score
  FROM
    admission_features
),

admission_with_cat AS (
  SELECT
    *,
    CASE
      WHEN charlson_score <= 1 THEN '0-1'
      WHEN charlson_score = 2 THEN '2'
      ELSE '>=3'
    END AS charlson_cat
  FROM
    admission_with_charlson
)

-- Final aggregation: by ICU vs no-ICU, LOS category, Charlson category
SELECT
  icu_flag,
  los_cat,
  charlson_cat,
  COUNT(1) AS n_admissions,
  SUM(hospital_expire_flag) AS deaths,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) AS mortality_prop,
  -- 95% CI for mortality (normal approx)
  GREATEST(0.0, SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) - 1.96 * SQRT( SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1))) / NULLIF(COUNT(1),0) )) AS mortality_ci_lower,
  LEAST(1.0, SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) + 1.96 * SQRT( SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1))) / NULLIF(COUNT(1),0) )) AS mortality_ci_upper,
  -- mechanical ventilation prevalence
  SUM(mech_vent) AS n_mech_vent,
  SAFE_DIVIDE(SUM(mech_vent), COUNT(1)) AS mech_vent_prop,
  GREATEST(0.0, SAFE_DIVIDE(SUM(mech_vent), COUNT(1)) - 1.96 * SQRT( SAFE_DIVIDE(SUM(mech_vent), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(mech_vent), COUNT(1))) / NULLIF(COUNT(1),0) )) AS mech_vent_ci_lower,
  LEAST(1.0, SAFE_DIVIDE(SUM(mech_vent), COUNT(1)) + 1.96 * SQRT( SAFE_DIVIDE(SUM(mech_vent), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(mech_vent), COUNT(1))) / NULLIF(COUNT(1),0) )) AS mech_vent_ci_upper,
  -- vasopressor prevalence
  SUM(vasopressor) AS n_vasopressor,
  SAFE_DIVIDE(SUM(vasopressor), COUNT(1)) AS vasopressor_prop,
  GREATEST(0.0, SAFE_DIVIDE(SUM(vasopressor), COUNT(1)) - 1.96 * SQRT( SAFE_DIVIDE(SUM(vasopressor), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(vasopressor), COUNT(1))) / NULLIF(COUNT(1),0) )) AS vasopressor_ci_lower,
  LEAST(1.0, SAFE_DIVIDE(SUM(vasopressor), COUNT(1)) + 1.96 * SQRT( SAFE_DIVIDE(SUM(vasopressor), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(vasopressor), COUNT(1))) / NULLIF(COUNT(1),0) )) AS vasopressor_ci_upper,
  -- RRT prevalence
  SUM(rrt) AS n_rrt,
  SAFE_DIVIDE(SUM(rrt), COUNT(1)) AS rrt_prop,
  GREATEST(0.0, SAFE_DIVIDE(SUM(rrt), COUNT(1)) - 1.96 * SQRT( SAFE_DIVIDE(SUM(rrt), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(rrt), COUNT(1))) / NULLIF(COUNT(1),0) )) AS rrt_ci_lower,
  LEAST(1.0, SAFE_DIVIDE(SUM(rrt), COUNT(1)) + 1.96 * SQRT( SAFE_DIVIDE(SUM(rrt), COUNT(1)) * (1 - SAFE_DIVIDE(SUM(rrt), COUNT(1))) / NULLIF(COUNT(1),0) )) AS rrt_ci_upper
FROM
  admission_with_cat
GROUP BY
  icu_flag,
  los_cat,
  charlson_cat
ORDER BY
  icu_flag DESC,
  los_cat,
  charlson_cat;