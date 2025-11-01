WITH
-- Base admissions augmented with hospital LOS and in-hospital mortality
adm_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mort_in_hosp,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS hosp_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- ICU LOS per admission (sum across all ICU stays for the same admission)
icu_los AS (
  SELECT
    i.hadm_id,
    SUM(i.los) AS icu_los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  GROUP BY i.hadm_id
),

-- ICU presence and LOS details per admission, now including hospital LOS for non-ICU cases
icu_presence AS (
  SELECT
    a.hadm_id,
    CASE WHEN COALESCE(il.icu_los_days, 0) > 0 THEN 1 ELSE 0 END AS icu_present,
    COALESCE(il.icu_los_days, 0) AS icu_los_days,
    a.hosp_los_days
  FROM adm_base a
  LEFT JOIN icu_los il
    ON a.hadm_id = il.hadm_id
),

-- Charlson-like comorbidity count per hadm_id (approximate, unweighted)
charlson_map AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%myocardial infarction%' OR LOWER(ld.long_title) LIKE '%infarction%' THEN 1 ELSE 0 END) AS has_MI,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%congestive heart failure%' OR LOWER(ld.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_CHF,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%peripheral vascular%' THEN 1 ELSE 0 END) AS has_PVD,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%cerebrovascular%' THEN 1 ELSE 0 END) AS has_CerebroVasc,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%dementia%' THEN 1 ELSE 0 END) AS has_Dementia,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%chronic pulmonary pneumonia%' THEN 1 ELSE 0 END) AS has_COPD,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%rheumatic%' THEN 1 ELSE 0 END) AS has_Rheumatic,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%peptic ulcer%' THEN 1 ELSE 0 END) AS has_PepticUlcer,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%mild liver%' OR LOWER(ld.long_title) LIKE '%liver disease%' THEN 1 ELSE 0 END) AS has_MildLiver,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%diabetes without complications%' THEN 1 ELSE 0 END) AS has_DM_NoComp,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%diabetes with complications%' OR LOWER(ld.long_title) LIKE '%diabetes with end-organ damage%' THEN 1 ELSE 0 END) AS has_DM_EndOrgan,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%paraplegia%' OR LOWER(ld.long_title) LIKE '%hemiplegia%' THEN 1 ELSE 0 END) AS has_Paraplegia,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%renal failure%' OR LOWER(ld.long_title) LIKE '%renal%' THEN 1 ELSE 0 END) AS has_Renal,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%cancer%' OR LOWER(ld.long_title) LIKE '%neoplasm%' THEN 1 ELSE 0 END) AS has_Cancer,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%metastatic%' THEN 1 ELSE 0 END) AS has_Metastatic,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%aids%' OR LOWER(ld.long_title) LIKE '%hiv%' THEN 1 ELSE 0 END) AS has_AIDS
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ld
    ON d.icd_code = ld.icd_code AND d.icd_version = ld.icd_version
  GROUP BY d.hadm_id
),

charlson_count AS (
  SELECT hadm_id,
         (has_MI + has_CHF + has_PVD + has_CerebroVasc + has_Dementia +
          has_COPD + has_Rheumatic + has_PepticUlcer + has_MildLiver +
          has_DM_NoComp + has_DM_EndOrgan + has_Paraplegia +
          has_Renal + has_Cancer + has_Metastatic + has_AIDS) AS charlson_count
  FROM charlson_map
),

-- Ventilation: ICU inputevents itemids for ventilators
vent_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%vent%' OR LOWER(label) LIKE '%ventilation%'
),

vent_per_hadm AS (
  SELECT ie.hadm_id,
         MAX(CASE WHEN ie.itemid IN (SELECT itemid FROM vent_itemids) THEN 1 ELSE 0 END) AS vent_present
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  GROUP BY ie.hadm_id
),

-- Vasopressors: ICU inputevents itemids for common vasopressors
vasop_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%norepinephrine%' OR LOWER(label) LIKE '%epinephrine%'
     OR LOWER(label) LIKE '%vasopressin%' OR LOWER(label) LIKE '%dopamine%' OR LOWER(label) LIKE '%phenylephrine%'
),

vasop_per_hadm AS (
  SELECT ie.hadm_id,
         MAX(CASE WHEN ie.itemid IN (SELECT itemid FROM vasop_itemids) THEN 1 ELSE 0 END) AS vasop_present
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  GROUP BY ie.hadm_id
),

rrt_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%' OR LOWER(label) LIKE '%renal replacement%'
),

rrt_per_hadm AS (
  SELECT ie.hadm_id,
         MAX(CASE WHEN ie.itemid IN (SELECT itemid FROM rrt_itemids) THEN 1 ELSE 0 END) AS rrt_present
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  GROUP BY ie.hadm_id
)

-- Final aggregation: ICU vs Non-ICU, LOS bins, Charlson categories with mortality and interventions
SELECT
  icu_group,
  los_bin,
  char_cat,
  COUNT(*) AS n_patients,
  SUM(a.mort_in_hosp) AS deaths,
  ROUND(100.0 * SUM(a.mort_in_hosp) / COUNT(*), 2) AS mortality_pct,
  ROUND(100.0 * SUM(IFNULL(v.vent_present, 0)) / COUNT(*), 2) AS vent_pct,
  ROUND(100.0 * SUM(IFNULL(pas.vasop_present, 0)) / COUNT(*), 2) AS vasop_pct,
  ROUND(100.0 * SUM(IFNULL(rtr.rrt_present, 0)) / COUNT(*), 2) AS rrt_pct
FROM (
  -- Core admission rows with mortality and LOS
  SELECT
    a.subject_id,
    a.hadm_id,
    a.mort_in_hosp,
    a.hosp_los_days,
    CASE WHEN p.icu_present = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    CASE
      WHEN p.icu_present = 1 THEN
        CASE WHEN p.icu_los_days <= 3 THEN '≤3'
             WHEN p.icu_los_days <= 6 THEN '4-6'
             WHEN p.icu_los_days <= 10 THEN '7-10'
             ELSE '>10'
        END
      ELSE
        CASE WHEN a.hosp_los_days <= 3 THEN '≤3'
             WHEN a.hosp_los_days <= 6 THEN '4-6'
             WHEN a.hosp_los_days <= 10 THEN '7-10'
             ELSE '>10'
        END
    END AS los_bin,
    CASE WHEN c.charlson_count <= 3 THEN '≤3'
         WHEN c.charlson_count <= 5 THEN '4-5'
         ELSE '>5'
    END AS char_cat
  FROM adm_base a
  LEFT JOIN icu_presence p ON a.hadm_id = p.hadm_id
  LEFT JOIN charlson_count c ON a.hadm_id = c.hadm_id
) AS a
LEFT JOIN vent_per_hadm v ON a.hadm_id = v.hadm_id
LEFT JOIN vasop_per_hadm pas ON a.hadm_id = pas.hadm_id
LEFT JOIN rrt_per_hadm rtr ON a.hadm_id = rtr.hadm_id
GROUP BY icu_group, los_bin, char_cat
ORDER BY icu_group, los_bin, char_cat;