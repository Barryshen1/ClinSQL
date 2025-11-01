WITH cohort AS (
  -- Base cohort: females 82-92 with principal pneumonia admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn  -- Earliest admission per patient
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'J1[2-8]%'  -- Principal pneumonia
    AND a.admittime >= '2008-01-01'  -- Anchor year filter for age validity
),

risk_factors AS (
  -- Comorbidities from all diagnoses in admission
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE diag.subject_id = c.subject_id AND diag.hadm_id = c.hadm_id
          AND (diag.icd_code LIKE 'F02%' OR diag.icd_code LIKE 'G30%'  -- Dementia
               OR diag.icd_code LIKE 'I50%' OR diag.icd_code = 'I09.9'  -- CHF (simplified)
               OR diag.icd_code LIKE 'N18%'  -- CKD
               OR diag.icd_code LIKE 'I2[1-5]%' )  -- Prior MI
      ) THEN 1 ELSE 0 END AS has_comorb,
    (p.anchor_age - 80) AS age_points  -- 1 pt per year over 80
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON c.subject_id = p.subject_id
  WHERE c.rn = 1  -- One per patient
),

labs_vitals AS (
  -- First labs and vitals within 24h (join to ICU if available, else admission time)
  SELECT 
    rf.*,
    COALESCE(lab.wbc_risk, 0) AS wbc_risk,  -- >12k =1
    COALESCE(vit.sbp_val, 120) AS sbp_val   -- <90 =1
  FROM risk_factors rf
  LEFT JOIN (
    SELECT 
      le.subject_id, le.hadm_id, 
      MIN(CASE WHEN le.itemid = 5131 AND le.valuenum > 12000 THEN 1 ELSE 0 END) AS wbc_risk  -- WBC itemid
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
    WHERE le.charttime >= a.admittime AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      AND le.valuenum IS NOT NULL
    GROUP BY le.subject_id, le.hadm_id
  ) lab ON rf.subject_id = lab.subject_id AND rf.hadm_id = lab.hadm_id
  LEFT JOIN (
    SELECT 
      ce.subject_id, ce.hadm_id,
      MIN(ce.valuenum) AS sbp_val  -- First SBP
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ce.subject_id = icu.subject_id AND ce.stay_id = icu.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON ce.subject_id = a.subject_id AND icu.hadm_id = a.hadm_id
    WHERE ce.itemid = 220045  -- SBP
      AND ce.charttime >= a.admittime AND ce.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      AND ce.valuenum IS NOT NULL
    GROUP BY ce.subject_id, ce.hadm_id
  ) vit ON rf.subject_id = vit.subject_id AND rf.hadm_id = vit.hadm_id
),

scored_cohort AS (
  SELECT 
    lv.*,
    -- Composite score: comorb (1) + age_points + wbc_risk (1 if >12k) + sbp_risk (1 if <90)
    rf.has_comorb + rf.age_points + wbc_risk +
    CASE WHEN sbp_val < 90 THEN 1 ELSE 0 END AS risk_score,
    -- Outcomes
    CASE 
      WHEN hospital_expire_flag = 1 OR (dod IS NOT NULL AND DATE(dod) <= DATE(TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)))
      THEN 1 ELSE 0 
    END AS mortality_30d,
    -- Complications (post-admission codes)
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc
        WHERE dc.subject_id = lv.subject_id AND dc.hadm_id = lv.hadm_id
          AND dc.seq_num > 1  -- Secondary
          AND (dc.icd_code LIKE 'I21%' OR dc.icd_code LIKE 'I63%' OR dc.icd_code LIKE 'I4[7-9]%' OR dc.icd_code LIKE 'I50%')
      ) THEN 1 ELSE 0 END AS cv_comp,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dn
        WHERE dn.subject_id = lv.subject_id AND dn.hadm_id = lv.hadm_id
          AND dn.seq_num > 1
          AND (dn.icd_code LIKE 'F05%' OR dn.icd_code LIKE 'G40%' OR dn.icd_code = 'G93.4')
      ) THEN 1 ELSE 0 END AS neuro_comp,
    CASE WHEN hospital_expire_flag = 0 THEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) ELSE NULL END AS los_days
  FROM labs_vitals lv
  INNER JOIN risk_factors rf ON lv.subject_id = rf.subject_id  -- Align
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score ASC) AS quintile  -- Q1 lowest risk
  FROM scored_cohort
)

SELECT 
  quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(mortality_30d) * 100, 1) AS mortality_30d_pct,
  ROUND(AVG(cv_comp) * 100, 1) AS cv_comp_pct,
  ROUND(AVG(neuro_comp) * 100, 1) AS neuro_comp_pct,
  ROUND(PERCENTILE_CONT(0.5, los_days), 1) AS median_los_survivors
FROM quintiles
GROUP BY quintile
ORDER BY quintile;