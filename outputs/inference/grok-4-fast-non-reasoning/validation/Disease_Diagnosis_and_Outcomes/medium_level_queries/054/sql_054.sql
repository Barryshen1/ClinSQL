WITH cohort AS (
  -- Base cohort: 44yo male with postoperative complications (T81* principal dx)
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, D) AS LOS,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, D) <= 3 THEN '<=3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, D) BETWEEN 4 AND 6 THEN '4-6'
      WHEN DATE_DIFF(a.dischtime, a.admittime, D) BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_bin,
    -- ICU flag: any transfer to ICU during admission
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
        WHERE t.subject_id = a.subject_id 
          AND t.hadm_id = a.hadm_id 
          AND LOWER(t.careunit) LIKE '%icu%'
      ) THEN 1 ELSE 0 
    END AS is_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age = 44
    AND d.icd_code LIKE 'T81%'
    AND d.icd_version = '10'  -- ICD-10 for modern cases
    AND a.dischtime > a.admittime  -- Exclude same-day
    AND a.hospital_expire_flag IS NOT NULL
),

cci_weights AS (
  -- Simplified Charlson CCI calculation (Deyo adaptation for ICD-10)
  SELECT 
    hadm_id,
    SUM(weight) AS cci_score
  FROM (
    SELECT hadm_id, icd_code,
      CASE 
        -- MI
        WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' THEN 1
        -- CHF
        WHEN icd_code LIKE 'I09.9' OR icd_code LIKE 'I11.0' OR icd_code LIKE 'I13%' 
          OR icd_code LIKE 'I25.5' OR icd_code LIKE 'I42%' OR icd_code LIKE 'I43%' 
          OR icd_code LIKE 'I50%' THEN 1
        -- PVD
        WHEN icd_code LIKE 'I70%' THEN 1
        -- Dementia
        WHEN icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%' THEN 1
        -- COPD
        WHEN icd_code LIKE 'J40%' OR icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' 
          OR icd_code LIKE 'J43%' OR icd_code LIKE 'J44%' OR icd_code LIKE 'J47%' THEN 1
        -- Connective tissue disease
        WHEN icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M08%' 
          OR icd_code LIKE 'M12.0' OR icd_code LIKE 'M32%' OR icd_code LIKE 'M33%' 
          OR icd_code LIKE 'M34%' OR icd_code LIKE 'M35.1' OR icd_code LIKE 'M35.3' 
          OR icd_code LIKE 'M36.0' THEN 1
        -- Ulcer
        WHEN icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%' THEN 1
        -- Mild liver
        WHEN icd_code LIKE 'B18.0' OR icd_code = 'K70.0' OR icd_code LIKE 'I85%' 
          OR icd_code LIKE 'I86.4' OR icd_code LIKE 'I98.2' OR icd_code = 'K71.10' 
          OR icd_code LIKE 'K71.11' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' 
          OR icd_code LIKE 'K76.6' OR icd_code = 'K76.69' THEN 1
        -- DM uncomplicated
        WHEN icd_code LIKE 'E10.0' OR icd_code LIKE 'E10.1' OR icd_code LIKE 'E10.9' 
          OR icd_code LIKE 'E11.0' OR icd_code LIKE 'E11.1' OR icd_code LIKE 'E11.9' 
          OR icd_code LIKE 'E12.0' OR icd_code LIKE 'E12.1' OR icd_code LIKE 'E12.9' 
          OR icd_code LIKE 'E13.0' OR icd_code LIKE 'E13.1' OR icd_code LIKE 'E13.9' 
          OR icd_code LIKE 'O24.0' OR icd_code LIKE 'O24.4' THEN 1
        -- Hemiplegia
        WHEN icd_code LIKE 'G81%' OR icd_code LIKE 'G82%' OR icd_code = 'G041' THEN 2
        -- Moderate/severe renal
        WHEN icd_code LIKE 'I12%' OR icd_code LIKE 'I13.1' OR icd_code LIKE 'I13.2' 
          OR icd_code LIKE 'N18%' OR icd_code = 'N19' OR icd_code LIKE 'Z49.0' 
          OR icd_code LIKE 'Z49.1' OR icd_code LIKE 'Z99.2' OR icd_code LIKE 'E10.2' 
          OR icd_code LIKE 'E11.2' OR icd_code LIKE 'E13.2' THEN 2
        -- Diabetes with complications
        WHEN icd_code LIKE 'E10.2' OR icd_code LIKE 'E10.3' OR icd_code LIKE 'E10.4' 
          OR icd_code LIKE 'E11.2' OR icd_code LIKE 'E11.3' OR icd_code LIKE 'E11.4' 
          OR icd_code LIKE 'E12.2' OR icd_code LIKE 'E12.3' OR icd_code LIKE 'E12.4' 
          OR icd_code LIKE 'E13.2' OR icd_code LIKE 'E13.3' OR icd_code LIKE 'E13.4' 
          OR icd_code LIKE 'O24.1' OR icd_code LIKE 'O24.2' OR icd_code LIKE 'O24.3' THEN 2
        -- Malignancy (non-skin)
        WHEN icd_code LIKE 'C00%' OR icd_code LIKE 'C1%' OR icd_code LIKE 'C2%' OR icd_code LIKE 'C3%' 
          OR icd_code LIKE 'C4%' OR icd_code LIKE 'C5%' OR icd_code LIKE 'C6%' OR icd_code LIKE 'C7%' 
          OR icd_code LIKE 'C8%' OR icd_code LIKE 'C9%' OR icd_code LIKE 'D00%' OR icd_code LIKE 'D01%' 
          OR icd_code LIKE 'D02%' OR icd_code LIKE 'D37%' OR icd_code LIKE 'D48%' 
          OR icd_code LIKE 'D49.0' OR icd_code LIKE 'D49.1' OR icd_code LIKE 'D49.5' 
          OR icd_code LIKE 'D61.1' OR icd_code LIKE 'D63.0' OR icd_code LIKE 'D64.5' THEN 2
        -- Moderate liver
        WHEN icd_code = 'K70.0' OR icd_code LIKE 'K70.4' OR icd_code LIKE 'K72.1' 
          OR icd_code = 'I98.0' OR icd_code LIKE 'K71.1' OR icd_code LIKE 'K73.2' OR icd_code LIKE 'K76.0' THEN 2
        -- Metastatic cancer
        WHEN icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' OR icd_code LIKE 'C80%' THEN 3
        -- AIDS
        WHEN icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B24%' THEN 6
        ELSE 0
      END AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = '10'
  ) weights
  GROUP BY hadm_id
),

stratified_cohort AS (
  SELECT 
    c.*,
    COALESCE(cw.cci_score, 0) AS cci_score,
    CASE 
      WHEN COALESCE(cw.cci_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cw.cci_score, 0) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS cci_bin
  FROM cohort c
  LEFT JOIN cci_weights cw ON c.hadm_id = cw.hadm_id
  WHERE c.LOS > 0  -- Valid LOS
),

-- Reference mortality for <=3 days (per is_icu, cci_bin)
ref_mortality AS (
  SELECT 
    is_icu,
    cci_bin,
    AVG(CAST(hospital_expire_flag AS FLOAT)) * 100 AS ref_mort_pct
  FROM stratified_cohort
  WHERE los_bin = '<=3'
  GROUP BY is_icu, cci_bin
)

SELECT 
  sc.is_icu,
  sc.los_bin,
  sc.cci_bin,
  COUNT(*) AS n_patients,
  -- Mortality
  SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) * 100 AS mort_pct,
  COALESCE(rm.ref_mort_pct, 0) AS ref_mort_pct,
  SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) * 100 - COALESCE(rm.ref_mort_pct, 0) AS abs_diff_vs_ref,
  CASE 
    WHEN COALESCE(rm.ref_mort_pct, 0) > 0 
    THEN SAFE_DIVIDE(
      (SAFE_DIVIDE(SUM(sc.hospital_expire_flag), COUNT(*)) * 100 - COALESCE(rm.ref_mort_pct, 0)) / 
      COALESCE(rm.ref_mort_pct, 0), 1
    ) 
    ELSE NULL 
  END AS rel_diff_vs_ref,
  -- Interventions (% of admissions with any exposure)
  SAFE_DIVIDE(
    SUM(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE ie.hadm_id = sc.hadm_id 
        AND ie.itemid IN (225477, 225798, 227041, 227042, 30004, 30162)
      UNION ALL
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.hadm_id = sc.hadm_id 
        AND pe.itemid IN (225477, 720, 223848)
    ) THEN 1 ELSE 0 END), COUNT(*)
  ) * 100 AS pct_vent,
  SAFE_DIVIDE(
    SUM(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE ie.hadm_id = sc.hadm_id 
        AND ie.itemid IN (220615, 30047, 30120, 30307, 220606)
      UNION ALL
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      WHERE pr.hadm_id = sc.hadm_id
        AND (LOWER(pr.drug) LIKE '%norepinephrine%' 
          OR LOWER(pr.drug) LIKE '%epinephrine%' 
          OR LOWER(pr.drug) LIKE '%vasopressin%' 
          OR LOWER(pr.drug) LIKE '%phenylephrine%' 
          OR LOWER(pr.drug) LIKE '%dopamine%')
    ) THEN 1 ELSE 0 END), COUNT(*)
  ) * 100 AS pct_vaso,
  SAFE_DIVIDE(
    SUM(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE ie.hadm_id = sc.hadm_id 
        AND ie.itemid IN (1502, 1503, 225826)
      UNION ALL
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.hadm_id = sc.hadm_id 
        AND pe.itemid IN (1502)
      UNION ALL
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      WHERE pi.hadm_id = sc.hadm_id
        AND (pi.icd_code LIKE '5A1D%' OR pi.icd_code = '39.95')
    ) THEN 1 ELSE 0 END), COUNT(*)
  ) * 100 AS pct_rrt
FROM stratified_cohort sc
LEFT JOIN ref_mortality rm ON sc.is_icu = rm.is_icu AND sc.cci_bin = rm.cci_bin
GROUP BY sc.is_icu, sc.los_bin, sc.cci_bin, rm.ref_mort_pct
ORDER BY sc.is_icu, sc.cci_bin, 
  CASE sc.los_bin 
    WHEN '<=3' THEN 1 
    WHEN '4-6' THEN 2 
    WHEN '7-10' THEN 3 
    ELSE 4 
  END;