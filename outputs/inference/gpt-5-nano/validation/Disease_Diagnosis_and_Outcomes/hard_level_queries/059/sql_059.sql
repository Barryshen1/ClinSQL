with base_cohort as (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.dod,
    a.hospital_expire_flag,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    -- age at admission 59-69
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
),

-- 1) DKA cohort: male, age 59-69, admitted with DKA
dka_cohort AS (
  SELECT bc.*
  FROM base_cohort bc
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE di.subject_id = bc.subject_id
      AND di.hadm_id = bc.hadm_id
      AND (
        (di.icd_version = 9 AND di.icd_code LIKE '250.1%')
        OR (di.icd_version = 10 AND di.icd_code LIKE 'E10.1%')
        OR dd.long_title LIKE '%diabetic ketoacidosis%'
      )
  )
),

-- 2) Matched general inpatient cohort (age 59-69, male)
matched_cohort AS (
  SELECT bc.*
  FROM base_cohort bc
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE di.subject_id = bc.subject_id
      AND di.hadm_id = bc.hadm_id
      AND (
        (di.icd_version = 9 AND di.icd_code LIKE '250.1%')
        OR (di.icd_version = 10 AND di.icd_code LIKE 'E10.1%')
        OR dd.long_title LIKE '%diabetic ketoacidosis%'
      )
  )
),

-- 3) Risk flags for the entire cohort (DKA + Matched)
risk_flags_all AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.dod,
    c.hospital_expire_flag,
    c.age_at_admit,
    c.gender,
    MAX(CASE WHEN dd_MI.long_title LIKE '%myocardial%' OR dd_MI.long_title LIKE '%infarction%' THEN 1 ELSE 0 END) AS has_MI,
    MAX(CASE WHEN dd_CHF.long_title LIKE '%congestive heart failure%' OR dd_CHF.long_title LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_CHF,
    MAX(CASE WHEN dd_PVD.long_title LIKE '%peripheral vascular%' THEN 1 ELSE 0 END) AS has_PVD,
    MAX(CASE WHEN dd_CVD.long_title LIKE '%cerebrovascular%' THEN 1 ELSE 0 END) AS has_CVD,
    MAX(CASE WHEN dd_Dementia.long_title LIKE '%dementia%' THEN 1 ELSE 0 END) AS has_Dementia,
    MAX(CASE WHEN dd_COPD.long_title LIKE '%COPD%' OR dd_COPD.long_title LIKE '%chronic pulmonary%' THEN 1 ELSE 0 END) AS has_COPD,
    MAX(CASE WHEN dd_DM_noComp.long_title LIKE '%diabetes mellitus without complications%' OR dd_DM_noComp.long_title LIKE '%diabetes without%' THEN 1 ELSE 0 END) AS has_DM_without_comp,
    MAX(CASE WHEN dd_DM_withComp.long_title LIKE '%diabetes mellitus with complications%' OR dd_DM_withComp.long_title LIKE '%diabetes with%' THEN 1 ELSE 0 END) AS has_DM_with_comp,
    MAX(CASE WHEN dd_Renal.long_title LIKE '%kidney%' OR dd_Renal.long_title LIKE '%renal%' THEN 1 ELSE 0 END) AS has_Renal,
    MAX(CASE WHEN dd_Liver.long_title LIKE '%liver%' OR dd_Liver.long_title LIKE '%hepatic%' THEN 1 ELSE 0 END) AS has_Liver,
    MAX(CASE WHEN dd_Malignancy.long_title LIKE '%malignancy%' OR dd_Malignancy.long_title LIKE '%neoplasm%' THEN 1 ELSE 0 END) AS has_Malignancy,
    MAX(CASE WHEN dd_Metastatic.long_title LIKE '%metastatic%' THEN 1 ELSE 0 END) AS has_Metastatic,
    MAX(CASE WHEN dd_AIDS.long_title LIKE '%AIDS%' THEN 1 ELSE 0 END) AS has_AIDS,
    MAX(CASE WHEN di_AKI.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_AKI,
    MAX(CASE WHEN di_ARDS.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_ARDS
  FROM (
    SELECT * FROM base_cohort
  ) c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_MI
    ON di_MI.subject_id = c.subject_id AND di_MI.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_MI
    ON di_MI.icd_code = dd_MI.icd_code AND di_MI.icd_version = dd_MI.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_CHF
    ON di_CHF.subject_id = c.subject_id AND di_CHF.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_CHF
    ON di_CHF.icd_code = dd_CHF.icd_code AND di_CHF.icd_version = dd_CHF.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_PVD
    ON di_PVD.subject_id = c.subject_id AND di_PVD.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_PVD
    ON di_PVD.icd_code = dd_PVD.icd_code AND di_PVD.icd_version = dd_PVD.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_CVD
    ON di_CVD.subject_id = c.subject_id AND di_CVD.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_CVD
    ON di_CVD.icd_code = dd_CVD.icd_code AND di_CVD.icd_version = dd_CVD.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_Dementia
    ON di_Dementia.subject_id = c.subject_id AND di_Dementia.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_Dementia
    ON di_Dementia.icd_code = dd_Dementia.icd_code AND di_Dementia.icd_version = dd_Dementia.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_COPD
    ON di_COPD.subject_id = c.subject_id AND di_COPD.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_COPD
    ON di_COPD.icd_code = dd_COPD.icd_code AND di_COPD.icd_version = dd_COPD.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_DM_noComp
    ON di_DM_noComp.subject_id = c.subject_id AND di_DM_noComp.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_DM_noComp
    ON di_DM_noComp.icd_code = dd_DM_noComp.icd_code AND di_DM_noComp.icd_version = dd_DM_noComp.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_DM_withComp
    ON di_DM_withComp.subject_id = c.subject_id AND di_DM_withComp.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_DM_withComp
    ON di_DM_withComp.icd_code = dd_DM_withComp.icd_code AND di_DM_withComp.icd_version = dd_DM_withComp.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_Renal
    ON di_Renal.subject_id = c.subject_id AND di_Renal.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_Renal
    ON di_Renal.icd_code = dd_Renal.icd_code AND di_Renal.icd_version = dd_Renal.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_Liver
    ON di_Liver.subject_id = c.subject_id AND di_Liver.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_Liver
    ON di_Liver.icd_code = dd_Liver.icd_code AND di_Liver.icd_version = dd_Liver.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_Malignancy
    ON di_Malignancy.subject_id = c.subject_id AND di_Malignancy.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_Malignancy
    ON di_Malignancy.icd_code = dd_Malignancy.icd_code AND di_Malignancy.icd_version = dd_Malignancy.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_Metastatic
    ON di_Metastatic.subject_id = c.subject_id AND di_Metastatic.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_Metastatic
    ON di_Metastatic.icd_code = dd_Metastatic.icd_code AND di_Metastatic.icd_version = dd_Metastatic.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_AIDS
    ON di_AIDS.subject_id = c.subject_id AND di_AIDS.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_AIDS
    ON di_AIDS.icd_code = dd_AIDS.icd_code AND di_AIDS.icd_version = dd_AIDS.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_AKI
    ON di_AKI.subject_id = c.subject_id AND di_AKI.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_AKI
    ON di_AKI.icd_code = dd_AKI.icd_code AND di_AKI.icd_version = dd_AKI.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ARDS
    ON di_ARDS.subject_id = c.subject_id AND di_ARDS.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_ARDS
    ON di_ARDS.icd_code = dd_ARDS.icd_code AND di_ARDS.icd_version = dd_ARDS.icd_version
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.dod, c.hospital_expire_flag, c.age_at_admit, c.gender
),

-- 4) Risk calculation for matched admissions
matched_risk_calc AS (
  SELECT mc.subject_id, mc.hadm_id, mc.admittime, mc.dischtime, mc.dod, mc.hospital_expire_flag, mc.age_at_admit, mc.gender,
         (IFNULL(rf.has_MI,0)*1
          + IFNULL(rf.has_CHF,0)*1
          + IFNULL(rf.has_PVD,0)*1
          + IFNULL(rf.has_CVD,0)*1
          + IFNULL(rf.has_Dementia,0)*1
          + IFNULL(rf.has_COPD,0)*1
          + IFNULL(rf.has_DM_without_comp,0)*1
          + IFNULL(rf.has_DM_with_comp,0)*2
          + IFNULL(rf.has_Renal,0)*2
          + IFNULL(rf.has_Liver,0)*1
          + IFNULL(rf.has_Malignancy,0)*2
          + IFNULL(rf.has_Metastatic,0)*6
          + IFNULL(rf.has_AIDS,0)*6) AS risk_score,
         CASE WHEN mc.dod IS NOT NULL AND DATE(mc.dod) >= DATE(mc.admittime)
              AND DATE_DIFF(DATE(mc.dod), DATE(mc.admittime), DAY) <= 30
              THEN 1 ELSE 0 END AS within_30d_mort,
         IFNULL(rf.has_AKI,0) AS has_AKI,
         IFNULL(rf.has_ARDS,0) AS has_ARDS,
         CASE WHEN mc.hospital_expire_flag = 0
              THEN DATE_DIFF(DATE(mc.dischtime), DATE(mc.admittime), DAY)
              ELSE NULL END AS survivor_los_days
  FROM matched_cohort mc
  LEFT JOIN risk_flags_all rf
    ON rf.subject_id = mc.subject_id AND rf.hadm_id = mc.hadm_id
),

-- 5) DKA risk (subset of matched risk) with percentile relative to all matched risks
dka_risk AS (
  SELECT m.subject_id, m.hadm_id, m.admittime, m.dischtime, m.dod, m.hospital_expire_flag,
         m.age_at_admit, m.gender,
         m.risk_score,
         CAST((SELECT COUNT(*) FROM matched_risk_calc mrc WHERE mrc.risk_score <= m.risk_score) AS FLOAT64)
           / CAST((SELECT COUNT(*) FROM matched_risk_calc) AS FLOAT64) AS risk_percentile_in_matched,
         m.within_30d_mort, m.has_AKI, m.has_ARDS, m.survivor_los_days
  FROM matched_risk_calc m
  WHERE EXISTS (
    SELECT 1 FROM dka_cohort d
    WHERE d.subject_id = m.subject_id AND d.hadm_id = m.hadm_id
  )
),

-- 6) Output: two rows (DKA vs Matched)
final AS (
  SELECT
    'DKA_59_69_M' AS group_label,
    AVG(risk_score) AS mean_risk_score,
    AVG(within_30d_mort) AS thirty_day_mortality_rate,
    AVG(has_AKI) AS aki_rate,
    AVG(has_ARDS) AS ards_rate,
    AVG(survivor_los_days) AS survivor_los_mean_days,
    AVG(risk_percentile_in_matched) AS avg_risk_percentile_in_matched
  FROM dka_risk

  UNION ALL

  SELECT
    'Matched_59_69_M' AS group_label,
    AVG(risk_score) AS mean_risk_score,
    AVG(within_30d_mort) AS thirty_day_mortality_rate,
    AVG(has_AKI) AS aki_rate,
    AVG(has_ARDS) AS ards_rate,
    AVG(survivor_los_days) AS survivor_los_mean_days,
    NULL AS avg_risk_percentile_in_matched
  FROM matched_risk_calc
)

SELECT *
FROM final;