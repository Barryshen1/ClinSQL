WITH hf_cohort AS (
  -- Base cohort: males 53-63 with HF admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.dischtime > a.admittime  -- Ensure valid admission
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_version = '10'
        AND d.icd_code LIKE 'I50%'
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 1  -- Exclude LOS=0 early
),

charlson_comorbidities AS (
  -- Calculate Charlson Comorbidity Index (CCI) per hadm_id using ICD-10 codes
  SELECT 
    hadm_id,
    -- MI (1)
    MAX(CASE WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I25.2%' THEN 1 ELSE 0 END) AS mi,
    -- CHF (1) - all have HF, but include
    MAX(CASE WHEN icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS chf,
    -- PVD (1)
    MAX(CASE WHEN icd_code LIKE 'I70%' OR icd_code LIKE 'I71%' OR icd_code LIKE 'I73.1%' 
             OR icd_code LIKE 'I73.8%' OR icd_code LIKE 'I73.9%' OR icd_code LIKE 'I77.1%' 
             OR icd_code LIKE 'K55.1%' OR icd_code LIKE 'K55.8%' OR icd_code LIKE 'Z95.9%' THEN 1 ELSE 0 END) AS pvd,
    -- Dementia (1)
    MAX(CASE WHEN icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%' 
             OR icd_code LIKE 'G30%' OR icd_code LIKE 'G31.0%' OR icd_code LIKE 'G31.83%' THEN 1 ELSE 0 END) AS dementia,
    -- COPD (1)
    MAX(CASE WHEN icd_code LIKE 'J40%' OR icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' OR icd_code LIKE 'J43%' 
             OR icd_code LIKE 'J44%' OR icd_code LIKE 'J47%' THEN 1 ELSE 0 END) AS copd,
    -- Connective tissue disease (1)
    MAX(CASE WHEN icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M08%' 
             OR icd_code LIKE 'M12%' OR icd_code LIKE 'M32%' OR icd_code LIKE 'M33%' 
             OR icd_code LIKE 'M34%' OR icd_code LIKE 'M35.1%' OR icd_code LIKE 'M35.3%' THEN 1 ELSE 0 END) AS ctd,
    -- Peptic ulcer (1)
    MAX(CASE WHEN icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%' THEN 1 ELSE 0 END) AS pu,
    -- Diabetes w/o complications (1)
    MAX(CASE WHEN icd_code LIKE 'E10.0%' OR icd_code LIKE 'E10.1%' OR icd_code LIKE 'E10.9%' 
             OR icd_code LIKE 'E11.0%' OR icd_code LIKE 'E11.1%' OR icd_code LIKE 'E11.9%' 
             OR icd_code LIKE 'E12.0%' OR icd_code LIKE 'E12.1%' OR icd_code LIKE 'E12.9%' 
             OR icd_code LIKE 'E13.0%' OR icd_code LIKE 'E13.1%' OR icd_code LIKE 'E13.9%' 
             OR icd_code LIKE 'E14.0%' OR icd_code LIKE 'E14.1%' OR icd_code LIKE 'E14.9%' THEN 1 ELSE 0 END) AS dm,
    -- Diabetes w/ complications (2)
    MAX(CASE WHEN icd_code LIKE 'E10.2%' OR icd_code LIKE 'E10.3%' OR icd_code LIKE 'E10.4%' 
             OR icd_code LIKE 'E11.2%' OR icd_code LIKE 'E11.3%' OR icd_code LIKE 'E11.4%' 
             OR icd_code LIKE 'E12.2%' OR icd_code LIKE 'E12.3%' OR icd_code LIKE 'E12.4%' 
             OR icd_code LIKE 'E13.2%' OR icd_code LIKE 'E13.3%' OR icd_code LIKE 'E13.4%' 
             OR icd_code LIKE 'E14.2%' OR icd_code LIKE 'E14.3%' OR icd_code LIKE 'E14.4%' THEN 1 ELSE 0 END) AS dm_cx,
    -- Paraplegia (2)
    MAX(CASE WHEN icd_code LIKE 'G81.1%' OR icd_code LIKE 'G82%' OR icd_code LIKE 'G83.2%' 
             OR icd_code LIKE 'G83.4%' THEN 1 ELSE 0 END) AS paraplegia,
    -- Renal disease (2) - Refined to specific renal codes
    MAX(CASE WHEN icd_code LIKE 'I12%' OR icd_code LIKE 'I13.0%' OR icd_code LIKE 'I13.1%' 
             OR icd_code LIKE 'N17%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' 
             OR icd_code LIKE 'Z49.0%' OR icd_code LIKE 'Z49.1%' OR icd_code LIKE 'Z99.2%' THEN 1 ELSE 0 END) AS renal,
    -- Cancer (2)
    MAX(CASE WHEN icd_code LIKE 'C%' THEN 1 ELSE 0 END) AS cancer,
    -- Moderate/severe liver disease (2 for mod, 3 for severe) - Simplified, remove overlap
    MAX(CASE WHEN icd_code LIKE 'K70.0%' OR icd_code LIKE 'K70.4%' OR icd_code LIKE 'K71.1%' 
             OR icd_code LIKE 'K72%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' 
             OR icd_code LIKE 'K76.6%' OR icd_code LIKE 'I85%' OR icd_code LIKE 'I86.4%' 
             OR icd_code LIKE 'I98.2%' THEN 1 ELSE 0 END) AS liver_mod,
    MAX(CASE WHEN icd_code LIKE 'K70.4%' OR icd_code LIKE 'I85.0%' OR icd_code LIKE 'I98.0%' THEN 1 ELSE 0 END) AS liver_severe,
    -- Metastatic cancer (3)
    MAX(CASE WHEN icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' OR icd_code LIKE 'C80%' THEN 1 ELSE 0 END) AS met_cancer,
    -- HIV/AIDS (6)
    MAX(CASE WHEN icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B24%' THEN 1 ELSE 0 END) AS hiv
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = '10'
  GROUP BY hadm_id
),

charlson_scores AS (
  SELECT 
    hadm_id,
    -- Sum weighted scores (ensure INT64 types)
    (COALESCE(mi, 0) * 1) +
    (COALESCE(chf, 0) * 1) +
    (COALESCE(pvd, 0) * 1) +
    (COALESCE(dementia, 0) * 1) +
    (COALESCE(copd, 0) * 1) +
    (COALESCE(ctd, 0) * 1) +
    (COALESCE(pu, 0) * 1) +
    (COALESCE(dm, 0) * 1) +
    (COALESCE(dm_cx, 0) * 2) +
    (COALESCE(paraplegia, 0) * 2) +
    (COALESCE(renal, 0) * 2) +
    (COALESCE(cancer, 0) * 2) +
    (COALESCE(liver_mod, 0) * 2) +
    (COALESCE(liver_severe, 0) * 3) +
    (COALESCE(met_cancer, 0) * 3) +
    (COALESCE(hiv, 0) * 6) AS cci
  FROM charlson_comorbidities
),

stratified_data AS (
  -- Main query: Stratify by LOS bin and CCI bin, compute metrics
  SELECT 
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_bin,
    CASE 
      WHEN COALESCE(cs.cci, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cs.cci, 0) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS cci_bin,
    -- Mortality %
    ROUND((SUM(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) / COUNT(*) * 100), 2) AS mortality_pct,
    COUNT(*) AS n_patients,
    -- Discharge % (refined string matching for common MIMIC values; exclude dead from non-hospice)
    ROUND((SUM(CASE WHEN LOWER(discharge_location) IN ('home', 'discharged to home', 'home with home iv provider') 
                    AND LOWER(discharge_location) NOT LIKE '%dead%' THEN 1.0 ELSE 0 END) / COUNT(*) * 100), 2) AS home_pct,
    ROUND((SUM(CASE WHEN LOWER(discharge_location) LIKE '%rehab%' OR discharge_location = 'LONG TERM CARE HOSPITAL'
                    AND LOWER(discharge_location) NOT LIKE '%dead%' THEN 1.0 ELSE 0 END) / COUNT(*) * 100), 2) AS rehab_pct,
    ROUND((SUM(CASE WHEN LOWER(discharge_location) LIKE '%snf%' OR LOWER(discharge_location) LIKE '%nursing%' OR discharge_location = 'SNF'
                    AND LOWER(discharge_location) NOT LIKE '%dead%' THEN 1.0 ELSE 0 END) / COUNT(*) * 100), 2) AS snf_pct,
    ROUND((SUM(CASE WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 1.0 ELSE 0 END) / COUNT(*) * 100), 2) AS hospice_pct
  FROM hf_cohort hc
  LEFT JOIN charlson_scores cs ON hc.hadm_id = cs.hadm_id  -- LEFT to include all admissions
  GROUP BY los_bin, cci_bin
),

los_diffs AS (
  -- Compute absolute and relative LOS differences (mortality: short vs long LOS within CCI)
  SELECT 
    *,
    -- Absolute diff: mortality (1-3 vs >=8)
    mortality_pct - LAG(mortality_pct) OVER (PARTITION BY cci_bin ORDER BY 
      CASE los_bin WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END
    ) AS abs_mort_diff_short_long,
    -- Relative diff: (long - short)/short * 100 (if short >0)
    CASE 
      WHEN LAG(mortality_pct) OVER (PARTITION BY cci_bin ORDER BY 
        CASE los_bin WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END
      ) > 0 
      THEN ROUND(((mortality_pct - LAG(mortality_pct) OVER (PARTITION BY cci_bin ORDER BY 
        CASE los_bin WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END
      )) / LAG(mortality_pct) OVER (PARTITION BY cci_bin ORDER BY 
        CASE los_bin WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END
      ) * 100), 2) 
      ELSE NULL 
    END AS rel_mort_diff_short_long_pct
  FROM stratified_data
  WHERE los_bin IN ('1-3', '>=8')  -- Only for short vs long comparison
)
SELECT 
  los_bin,
  cci_bin,
  mortality_pct,
  n_patients,
  home_pct,
  rehab_pct,
  snf_pct,
  hospice_pct,
  abs_mort_diff_short_long,
  rel_mort_diff_short_long_pct
FROM los_diffs
UNION ALL
-- Include mid LOS bin (4-7) without diffs
SELECT 
  los_bin,
  cci_bin,
  mortality_pct,
  n_patients,
  home_pct,
  rehab_pct,
  snf_pct,
  hospice_pct,
  NULL AS abs_mort_diff_short_long,
  NULL AS rel_mort_diff_short_long_pct
FROM stratified_data
WHERE los_bin = '4-7'
ORDER BY 
  CASE los_bin 
    WHEN '1-3' THEN 1 
    WHEN '4-7' THEN 2 
    ELSE 3 
  END,
  CASE cci_bin 
    WHEN '<=3' THEN 1 
    WHEN '4-5' THEN 2 
    ELSE 3 
  END;