WITH charlson_weights AS (
  -- Myocardial Infarction (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1 AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  
  UNION ALL
  
  -- Congestive Heart Failure (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND (icd_code LIKE 'I50%' OR icd_code = 'I09.9' OR icd_code LIKE 'I11.0%' OR icd_code LIKE 'I13.0%' OR icd_code LIKE 'I13.2%'))
  
  UNION ALL
  
  -- Peripheral Vascular Disease (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '441%' OR icd_code LIKE '443.1%' OR icd_code LIKE '443.2%' OR icd_code LIKE '443.8%' OR icd_code LIKE '445.1%' OR icd_code LIKE '445.7%' OR icd_code = 'V43.4'))
     OR (icd_version = 10 AND (icd_code LIKE 'I70%' OR icd_code LIKE 'I71.2%' OR icd_code LIKE 'I71.3%' OR icd_code LIKE 'I71.4%' OR icd_code LIKE 'I71.8%' OR icd_code LIKE 'I71.9%' OR icd_code LIKE 'K55.1%' OR icd_code LIKE 'K95.8%'))
  
  UNION ALL
  
  -- Cerebrovascular Disease (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code BETWEEN '430' AND '438')
     OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I6[0-9]'))
  
  UNION ALL
  
  -- Dementia (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '290%')
     OR (icd_version = 10 AND (icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%'))
  
  UNION ALL
  
  -- Chronic Pulmonary Disease (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '490%' OR icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '493%' OR icd_code LIKE '494%' OR icd_code LIKE '495%' OR icd_code LIKE '496%' OR icd_code LIKE '500%' OR icd_code LIKE '501%' OR icd_code LIKE '502%' OR icd_code LIKE '503%' OR icd_code LIKE '504%' OR icd_code LIKE '505%' OR icd_code = '506.4' OR icd_code = '508.1' OR icd_code = '508.8'))
     OR (icd_version = 10 AND (icd_code LIKE 'J40%' OR icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' OR icd_code LIKE 'J43%' OR icd_code LIKE 'J44%' OR icd_code LIKE 'J47%' OR icd_code LIKE 'J60%' OR icd_code LIKE 'J67%' OR icd_code = 'J68.4' OR icd_code = 'J70.1'))
  
  UNION ALL
  
  -- Connective Tissue Disease (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '710%' OR icd_code = '711.2' OR icd_code = '712.3' OR icd_code LIKE '714.0%' OR icd_code LIKE '714.1%' OR icd_code LIKE '714.8%'))
     OR (icd_version = 10 AND (icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M08%' OR icd_code LIKE 'M12%' OR icd_code LIKE 'M32-M35%'))
  
  UNION ALL
  
  -- Peptic Ulcer Disease (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '531%' OR icd_code LIKE '532%' OR icd_code LIKE '533%' OR icd_code LIKE '534%'))
     OR (icd_version = 10 AND (icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%'))
  
  UNION ALL
  
  -- Uncomplicated Diabetes (weight 1)
  SELECT DISTINCT subject_id, hadm_id, 1
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '250.0%' OR icd_code LIKE '250.1%' OR icd_code LIKE '250.2%' OR icd_code LIKE '250.3%' OR icd_code LIKE '250.7%'))
     OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^E10\.[0-8]') OR icd_code LIKE 'E10.A1%' OR REGEXP_CONTAINS(icd_code, r'^E11\.[0-8]') OR icd_code LIKE 'E11.A1%' OR REGEXP_CONTAINS(icd_code, r'^E12\.[0-8]') OR icd_code LIKE 'E12.A1%' OR REGEXP_CONTAINS(icd_code, r'^E13\.[0-8]') OR icd_code LIKE 'E13.A1%' OR REGEXP_CONTAINS(icd_code, r'^E14\.[0-8]') OR icd_code LIKE 'E14.A1%'))
  
  UNION ALL
  
  -- Complicated Diabetes (weight 2)
  SELECT DISTINCT subject_id, hadm_id, 2
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '250.4%' OR icd_code LIKE '250.5%' OR icd_code LIKE '250.6%'))
     OR (icd_version = 10 AND ((icd_code LIKE 'E10.2%' OR REGEXP_CONTAINS(icd_code, r'^E10\.[3-4]')) OR (icd_code LIKE 'E11.2%' OR REGEXP_CONTAINS(icd_code, r'^E11\.[3-4]')) OR (icd_code LIKE 'E12.2%' OR REGEXP_CONTAINS(icd_code, r'^E12\.[3-4]')) OR (icd_code LIKE 'E13.2%' OR REGEXP_CONTAINS(icd_code, r'^E13\.[3-4]')) OR (icd_code LIKE 'E14.2%' OR REGEXP_CONTAINS(icd_code, r'^E14\.[3-4]'))))
  
  UNION ALL
  
  -- Paraplegia (weight 2)
  SELECT DISTINCT subject_id, hadm_id, 2
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '342%' OR icd_code LIKE '343%' OR icd_code LIKE '344%'))
     OR (icd_version = 10 AND (icd_code LIKE 'G81.1%' OR icd_code LIKE 'G82%'))
  
  UNION ALL
  
  -- Renal Disease (weight 2)
  SELECT DISTINCT subject_id, hadm_id, 2
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '582%' OR icd_code LIKE '583.4%' OR icd_code LIKE '583.5%' OR icd_code LIKE '583.6%' OR icd_code LIKE '583.7%' OR icd_code = '585' OR icd_code = '586' OR icd_code = 'V42.0' OR icd_code LIKE 'V56%'))
     OR (icd_version = 10 AND (icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code LIKE 'N25.0%' OR icd_code = 'Z49.0' OR icd_code LIKE 'Z99.2%'))
  
  UNION ALL
  
  -- Cancer (weight 2) - non-metastatic
  SELECT DISTINCT subject_id, hadm_id, 2
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (REGEXP_CONTAINS(icd_code, r'^14[0-8]') OR REGEXP_CONTAINS(icd_code, r'^15[0-2]') OR REGEXP_CONTAINS(icd_code, r'^16[0-8]') OR REGEXP_CONTAINS(icd_code, r'^17[0-9]') OR REGEXP_CONTAINS(icd_code, r'^18[0-3]') OR REGEXP_CONTAINS(icd_code, r'^18[5-9]') OR REGEXP_CONTAINS(icd_code, r'^19[0-4]') OR REGEXP_CONTAINS(icd_code, r'^20[0-9]') OR REGEXP_CONTAINS(icd_code, r'^21[0-9]') OR REGEXP_CONTAINS(icd_code, r'^22[0-9]') OR REGEXP_CONTAINS(icd_code, r'^23[0-9]') OR REGEXP_CONTAINS(icd_code, r'^24[0-9]') OR REGEXP_CONTAINS(icd_code, r'^25[0-3]') OR REGEXP_CONTAINS(icd_code, r'^25[8-9]') OR REGEXP_CONTAINS(icd_code, r'^26[0-9]') OR REGEXP_CONTAINS(icd_code, r'^27[0-9]') OR REGEXP_CONTAINS(icd_code, r'^28[8-9]') OR REGEXP_CONTAINS(icd_code, r'^29[0-9]') OR REGEXP_CONTAINS(icd_code, r'^30[0-9]') OR REGEXP_CONTAINS(icd_code, r'^31[0-9]') OR REGEXP_CONTAINS(icd_code, r'^32[0-9]') OR REGEXP_CONTAINS(icd_code, r'^33[0-9]') OR REGEXP_CONTAINS(icd_code, r'^34[0-9]') OR REGEXP_CONTAINS(icd_code, r'^35[0-9]') OR REGEXP_CONTAINS(icd_code, r'^36[0-9]') OR REGEXP_CONTAINS(icd_code, r'^37[0-9]') OR REGEXP_CONTAINS(icd_code, r'^38[0-9]') OR REGEXP_CONTAINS(icd_code, r'^39[0-9]'))) -- solid tumors excl skin
     OR (icd_version = 10 AND (
       (icd_code >= 'C00' AND icd_code < 'C27') OR
       (icd_code >= 'C30' AND icd_code < 'C42') OR
       (icd_code >= 'C45' AND icd_code < 'C98')
     )) -- solid tumors excl skin C44
  
  UNION ALL
  
  -- Moderate/Severe Liver Disease (weight 3)
  SELECT DISTINCT subject_id, hadm_id, 3
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code = '456.0' OR icd_code = '456.1' OR icd_code LIKE '572.2%' OR icd_code LIKE '572.4%' OR icd_code LIKE '572.8%' OR icd_code = '573.5'))
     OR (icd_version = 10 AND (icd_code LIKE 'I85%' OR icd_code LIKE 'I86.4%' OR icd_code LIKE 'I98.2%' OR REGEXP_CONTAINS(icd_code, r'^K70\.0|K70\.[1-4]') OR icd_code LIKE 'K70.9%' OR icd_code LIKE 'K71.1%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' OR icd_code LIKE 'K76.6%'))
  
  UNION ALL
  
  -- Metastatic Cancer (weight 6)
  SELECT DISTINCT subject_id, hadm_id, 6
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '196%' OR icd_code LIKE '197%' OR icd_code LIKE '198%' OR icd_code LIKE '199%'))
     OR (icd_version = 10 AND icd_code LIKE 'C77-C80%')
  
  UNION ALL
  
  -- HIV/AIDS (weight 6)
  SELECT DISTINCT subject_id, hadm_id, 6
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '042%' OR icd_code LIKE '043%' OR icd_code LIKE '044%'))
     OR (icd_version = 10 AND icd_code LIKE 'B20-B24%')
),
cci AS (
  SELECT hadm_id, SUM(weight) AS charlson_score
  FROM charlson_weights
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '<=3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 6 THEN '4-6'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 10 THEN '7-10'
      ELSE '>10'
    END AS los_bin,
    COALESCE(c.charlson_score, 0) AS charlson_raw,
    CASE 
      WHEN COALESCE(c.charlson_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(c.charlson_score, 0) <= 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_bin,
    CASE WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) THEN 1 ELSE 0 END AS is_icu,
    -- Mortality flag (already in hospital_expire_flag)
    -- Vent flag
    CASE 
      WHEN NOT EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) THEN 0
      ELSE CASE WHEN EXISTS(
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.stay_id = i.stay_id 
        WHERE i.hadm_id = a.hadm_id AND ce.itemid BETWEEN 720 AND 727
      ) THEN 1 ELSE 0 END
    END AS flag_vent,
    -- Vaso flag
    CASE 
      WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) THEN 
        CASE WHEN EXISTS(
          SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie 
          JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ie.stay_id = i.stay_id 
          WHERE i.hadm_id = a.hadm_id 
            AND ie.itemid IN (220615, 221289, 221906, 222315, 223062, 228532, 228546, 30047, 30120, 30307, 30355)
            AND ie.amount > 0
        ) THEN 1 ELSE 0 END
      ELSE 
        CASE WHEN EXISTS(
          SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
          WHERE pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
            AND (LOWER(pr.drug) LIKE '%norepinephrine%' OR LOWER(pr.drug) LIKE '%phenylephrine%' OR LOWER(pr.drug) LIKE '%vasopressin%' 
                 OR LOWER(pr.drug) LIKE '%epinephrine%' OR LOWER(pr.drug) LIKE '%dopamine%')
        ) THEN 1 ELSE 0 END
    END AS flag_vaso,
    -- RRT flag
    CASE 
      WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) THEN 
        CASE WHEN EXISTS(
          SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
          JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON pe.stay_id = i.stay_id 
          WHERE i.hadm_id = a.hadm_id 
            AND pe.itemid IN (224244, 225456, 225457, 225458, 225464, 225466, 290925, 30365)
        ) THEN 1 ELSE 0 END
      ELSE 
        CASE WHEN EXISTS(
          SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
          WHERE pi.subject_id = a.subject_id AND pi.hadm_id = a.hadm_id
            AND ((pi.icd_version = 9 AND pi.icd_code = '39.95')
                 OR (pi.icd_version = 10 AND (pi.icd_code LIKE '5A1D%' OR pi.icd_code LIKE '5A2D%')))
        ) THEN 1 ELSE 0 END
    END AS flag_rrt
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN cci ON a.hadm_id = cci.hadm_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age = 44
    AND EXISTS(
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND ((d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^99[6-9]'))
             OR (d.icd_version = 10 AND d.icd_code LIKE 'T8%'))
    )
    AND a.admittime < a.dischtime
),
strata AS (
  SELECT 
    is_icu,
    los_bin,
    charlson_bin,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS mort_count,
    SUM(flag_vent) AS vent_count,
    SUM(flag_vaso) AS vaso_count,
    SUM(flag_rrt) AS rrt_count
  FROM cohort
  GROUP BY is_icu, los_bin, charlson_bin
  HAVING n > 0
),
base_mort AS (
  SELECT 
    is_icu,
    charlson_bin,
    (SUM(hospital_expire_flag) * 1.0 / COUNT(*)) * 100 AS base_mort_pct
  FROM cohort
  WHERE los_bin = '<=3'
  GROUP BY is_icu, charlson_bin
)
SELECT 
  s.is_icu,
  CASE s.is_icu WHEN 1 THEN 'ICU' ELSE 'Non-ICU' END AS is_icu_label,
  s.charlson_bin,
  s.los_bin,
  s.n,
  ROUND((s.mort_count * 1.0 / s.n) * 100, 2) AS mortality_pct,
  ROUND((s.vent_count * 1.0 / s.n) * 100, 2) AS vent_pct,
  ROUND((s.vaso_count * 1.0 / s.n) * 100, 2) AS vaso_pct,
  ROUND((s.rrt_count * 1.0 / s.n) * 100, 2) AS rrt_pct,
  ROUND(COALESCE((s.mort_count * 1.0 / s.n * 100 - b.base_mort_pct), 0), 2) AS abs_diff_mort,
  ROUND(
    CASE 
      WHEN b.base_mort_pct > 0 AND s.los_bin != '<=3' THEN ((s.mort_count * 1.0 / s.n * 100 - b.base_mort_pct) / b.base_mort_pct) * 100 
      ELSE NULL 
    END, 2
  ) AS rel_diff_mort_pct
FROM strata s
LEFT JOIN base_mort b ON s.is_icu = b.is_icu AND s.charlson_bin = b.charlson_bin
ORDER BY s.is_icu, s.charlson_bin, 
  CASE s.los_bin 
    WHEN '<=3' THEN 1 
    WHEN '4-6' THEN 2 
    WHEN '7-10' THEN 3 
    ELSE 4 
  END;