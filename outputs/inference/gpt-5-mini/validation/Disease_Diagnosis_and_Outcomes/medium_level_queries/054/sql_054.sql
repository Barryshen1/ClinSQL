WITH
-- 1) Admissions for 44-year-old males
male_adms AS (
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age = 44
),

-- 2) Identify admissions with a diagnosis suggestive of postoperative complications
postop_adms AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    LOWER(COALESCE(CAST(dd.long_title AS STRING), '')) LIKE '%postoperative%'
    OR LOWER(COALESCE(CAST(dd.long_title AS STRING), '')) LIKE '%post-operative%'
    OR LOWER(COALESCE(CAST(dd.long_title AS STRING), '')) LIKE '%post op%'
    OR (
      LOWER(COALESCE(CAST(dd.long_title AS STRING), '')) LIKE '%post%'
      AND LOWER(COALESCE(CAST(dd.long_title AS STRING), '')) LIKE '%complication%'
    )
  )
),

-- 3) Start with base admissions for cohort (male 44 and postop complication)
base AS (
  SELECT a.*
  FROM male_adms a
  JOIN postop_adms pa USING (hadm_id)
),

-- 4) Charlson condition flags per hadm_id (text-based mapping on diagnosis descriptions)
dx_text AS (
  SELECT d.hadm_id,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%myocardial infarction%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%acute myocardial%', 1, 0)) AS idx_mi,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%congestive heart failure%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%heart failure%', 1, 0)) AS idx_chf,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%peripheral vascular%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%peripheral vascular disease%', 1, 0)) AS idx_pvd,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%cerebrovascular%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%stroke%', 1, 0)) AS idx_cvd,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%dementia%', 1, 0)) AS idx_dementia,
    MAX(IF(
        LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%chronic obstructive pulmonary%' OR
        LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%copd%' OR
        LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%emphysema%' OR
        LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%chronic pulmonary%',
      1, 0)) AS idx_copd,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%rheumat%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%connective tissue%', 1, 0)) AS idx_rheum,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%peptic ulcer%', 1, 0)) AS idx_peptic,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%mild liver%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%chronic hepatitis%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%viral hepatitis%', 1, 0)) AS idx_liver_mild,
    -- Diabetes without/with complications
    MAX(IF(
      LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%diabetes%' AND
      (LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%with%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%complication%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%nephropathy%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%retinopathy%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%neuropathy%'),
      1, 0)) AS idx_dm_comp,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%diabetes%' AND NOT (
       LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%with%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%complication%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%nephropathy%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%retinopathy%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%neuropathy%'
      ), 1, 0)) AS idx_dm,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%hemiplegia%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%paraplegia%', 1, 0)) AS idx_hemi,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%renal%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%chronic kidney%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%ckd%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%renal failure%', 1, 0)) AS idx_renal,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%malign%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%carcinoma%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%neoplasm%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%leukemia%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%lymphoma%', 1, 0)) AS idx_tumor,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%metastat%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%secondary malignant%', 1, 0)) AS idx_metastatic,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%moderate%' AND LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%liver%', 1, 0)) AS idx_liver_modsev,
    MAX(IF(LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%aids%' OR LOWER(COALESCE(CAST(dd.long_title AS STRING),'')) LIKE '%hiv%', 1, 0)) AS idx_aids
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY d.hadm_id
),

-- 5) Compute Charlson score per hadm_id (approximate, text-based)
charlson AS (
  SELECT h.hadm_id,
    COALESCE(
      (IFNULL(dx.idx_mi,0) * 1)
    + (IFNULL(dx.idx_chf,0) * 1)
    + (IFNULL(dx.idx_pvd,0) * 1)
    + (IFNULL(dx.idx_cvd,0) * 1)
    + (IFNULL(dx.idx_dementia,0) * 1)
    + (IFNULL(dx.idx_copd,0) * 1)
    + (IFNULL(dx.idx_rheum,0) * 1)
    + (IFNULL(dx.idx_peptic,0) * 1)
    + (IFNULL(dx.idx_liver_mild,0) * 1)
    + (IFNULL(dx.idx_dm,0) * 1)
    + (IFNULL(dx.idx_dm_comp,0) * 2)
    + (IFNULL(dx.idx_hemi,0) * 2)
    + (IFNULL(dx.idx_renal,0) * 2)
    + (IFNULL(dx.idx_tumor,0) * 2)
    + (IFNULL(dx.idx_liver_modsev,0) * 3)
    + (IFNULL(dx.idx_metastatic,0) * 6)
    + (IFNULL(dx.idx_aids,0) * 6)
    , 0) AS charlson_score
  FROM (SELECT DISTINCT hadm_id FROM dx_text) h
  LEFT JOIN dx_text dx USING (hadm_id)
),

-- 6) Intervention flags per hadm_id
-- Mechanical ventilation via procedures_icd (and d_icd_procedures.long_title)
vent_procs AS (
  SELECT DISTINCT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE LOWER(COALESCE(CAST(dp.long_title AS STRING),'')) LIKE '%ventilat%'
     OR LEFT(CAST(p.icd_code AS STRING), 4) = '96.7'
),

-- Vasopressors via prescriptions and pharmacy text matching (common drug names)
vaso_rx AS (
  SELECT DISTINCT hadm_id
  FROM (
    SELECT hadm_id, LOWER(COALESCE(CAST(drug AS STRING),'')) as med FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    UNION ALL
    SELECT hadm_id, LOWER(COALESCE(CAST(medication AS STRING),'')) as med FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
    UNION ALL
    SELECT hadm_id, LOWER(COALESCE(CAST(medication AS STRING),'')) as med FROM `physionet-data.mimiciv_3_1_hosp.emar`
  )
  WHERE med LIKE '%norepinephrine%' OR med LIKE '%noradrenaline%' OR med LIKE '%epinephrine%' OR med LIKE '%adrenaline%'
     OR med LIKE '%phenylephrine%' OR med LIKE '%vasopressin%' OR med LIKE '%dopamine%' OR med LIKE '%dobutamine%'
),

-- RRT/dialysis via procedures and ICU procedureevents
rrt_procs AS (
  SELECT DISTINCT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE LOWER(COALESCE(CAST(dp.long_title AS STRING),'')) LIKE '%dialysis%' OR LOWER(COALESCE(CAST(dp.long_title AS STRING),'')) LIKE '%hemodial%'
),
rrt_proc_events_icu AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE LOWER(COALESCE(CAST(value AS STRING),'')) LIKE '%dialysis%' OR LOWER(COALESCE(CAST(ordercategoryname AS STRING),'')) LIKE '%dialysis%' OR LOWER(COALESCE(CAST(ordercategorydescription AS STRING),'')) LIKE '%dialysis%'
),

-- 7) Whether admission had any ICU stay
hadm_icu AS (
  SELECT DISTINCT hadm_id, 1 AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- 8) Combine base admissions with computed flags and metrics
admissions_enriched AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    DATE_DIFF(CAST(b.dischtime AS DATE), CAST(b.admittime AS DATE), DAY) + 1 AS los_days,
    CASE
      WHEN DATE_DIFF(CAST(b.dischtime AS DATE), CAST(b.admittime AS DATE), DAY) + 1 <= 3 THEN '<=3'
      WHEN DATE_DIFF(CAST(b.dischtime AS DATE), CAST(b.admittime AS DATE), DAY) + 1 BETWEEN 4 AND 6 THEN '4-6'
      WHEN DATE_DIFF(CAST(b.dischtime AS DATE), CAST(b.admittime AS DATE), DAY) + 1 BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_cat,
    CASE WHEN hi.had_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_flag,
    COALESCE(c.charlson_score, 0) AS charlson_score,
    -- Charlson category
    CASE
      WHEN COALESCE(c.charlson_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(c.charlson_score, 0) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_cat,
    -- interventions presence flags (1/0)
    IF(vp.hadm_id IS NOT NULL, 1, 0) AS mech_vent,
    IF(vx.hadm_id IS NOT NULL, 1, 0) AS vasopressor,
    IF(rr.hadm_id IS NOT NULL OR rr2.hadm_id IS NOT NULL, 1, 0) AS rrt
  FROM base b
  LEFT JOIN hadm_icu hi USING (hadm_id)
  LEFT JOIN charlson c USING (hadm_id)
  LEFT JOIN vent_procs vp USING (hadm_id)
  LEFT JOIN vaso_rx vx USING (hadm_id)
  LEFT JOIN rrt_procs rr USING (hadm_id)
  LEFT JOIN rrt_proc_events_icu rr2 USING (hadm_id)
),

-- 9) Aggregation by ICU status, LOS category, Charlson category
group_stats AS (
  SELECT
    icu_flag,
    los_cat,
    charlson_cat,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_pct,
    SUM(mech_vent) AS n_mech_vent,
    100.0 * SAFE_DIVIDE(SUM(mech_vent), COUNT(*)) AS mech_vent_pct,
    SUM(vasopressor) AS n_vasopressors,
    100.0 * SAFE_DIVIDE(SUM(vasopressor), COUNT(*)) AS vasopressor_pct,
    SUM(rrt) AS n_rrt,
    100.0 * SAFE_DIVIDE(SUM(rrt), COUNT(*)) AS rrt_pct
  FROM admissions_enriched
  GROUP BY icu_flag, los_cat, charlson_cat
),

-- 10) For each ICU/Charlson partition, find the mortality_pct where LOS <=3 (reference)
with_ref AS (
  SELECT
    gs.*,
    MAX(IF(los_cat = '<=3', mortality_pct, NULL)) OVER (PARTITION BY icu_flag, charlson_cat) AS ref_mortality_pct
  FROM group_stats gs
)

-- Final results: compute absolute and relative differences vs LOS <=3
SELECT
  icu_flag,
  charlson_cat,
  los_cat,
  n_admissions,
  n_deaths,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(ref_mortality_pct, 2) AS ref_mortality_pct_lte_3,
  ROUND(mortality_pct - ref_mortality_pct, 2) AS absolute_diff_pct_points_vs_lte_3,
  CASE
    WHEN ref_mortality_pct IS NULL OR ref_mortality_pct = 0 THEN NULL
    ELSE ROUND( (mortality_pct - ref_mortality_pct) / ref_mortality_pct * 100.0, 1)
  END AS relative_diff_percent_vs_lte_3,
  -- intervention percentages
  ROUND(mech_vent_pct, 2) AS mech_vent_pct,
  ROUND(vasopressor_pct, 2) AS vasopressor_pct,
  ROUND(rrt_pct, 2) AS rrt_pct
FROM with_ref
ORDER BY icu_flag DESC, charlson_cat,
  CASE los_cat WHEN '<=3' THEN 1 WHEN '4-6' THEN 2 WHEN '7-10' THEN 3 ELSE 4 END;