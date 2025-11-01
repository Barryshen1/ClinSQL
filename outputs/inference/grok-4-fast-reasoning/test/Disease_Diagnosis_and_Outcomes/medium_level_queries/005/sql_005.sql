WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 38 AND 48
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
    )
),
charlson_comps AS (
  SELECT 
    hadm_id,
    -- MI (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '412%'))
      OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code = 'I25.2'))
    THEN 1 ELSE 0 END) AS mi,
    -- CHF (1) - always 1 in this cohort, but computed
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '428%')
      OR (icd_version = 10 AND icd_code LIKE 'I50%')
    THEN 1 ELSE 0 END) AS chf,
    -- PVD (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '440%' OR icd_code LIKE '441%' OR icd_code LIKE '442%' OR icd_code LIKE '443%' OR icd_code LIKE '447%' OR icd_code LIKE '557.1%' OR icd_code LIKE '557.9%'))
      OR (icd_version = 10 AND (icd_code LIKE 'I70%' OR icd_code LIKE 'I71%' OR icd_code LIKE 'I72%' OR icd_code LIKE 'I73%' OR icd_code LIKE 'K55.1%' OR icd_code LIKE 'K95.8%'))
    THEN 1 ELSE 0 END) AS pvd,
    -- Stroke (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%' OR icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code LIKE '435%' OR icd_code LIKE '436%' OR icd_code LIKE '437%' OR icd_code LIKE '438%'))
      OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'G45%' OR icd_code LIKE 'H34.0%'))
    THEN 1 ELSE 0 END) AS stroke,
    -- Dementia (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '290%' OR icd_code = '294.1' OR icd_code = '331.2'))
      OR (icd_version = 10 AND (icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%' OR icd_code LIKE 'G30%'))
    THEN 1 ELSE 0 END) AS dementia,
    -- COPD (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '490%' OR icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '493%' OR icd_code LIKE '494%' OR icd_code LIKE '495%' OR icd_code LIKE '496%'))
      OR (icd_version = 10 AND (icd_code LIKE 'J40%' OR icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' OR icd_code LIKE 'J43%' OR icd_code LIKE 'J44%' OR icd_code = 'J47'))
    THEN 1 ELSE 0 END) AS copd,
    -- Connective tissue (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '710.0%' OR icd_code LIKE '710.1%' OR icd_code LIKE '710.2%' OR icd_code LIKE '710.3%' OR icd_code LIKE '710.4%' OR icd_code LIKE '710.9%' OR icd_code LIKE '714.0%' OR icd_code LIKE '714.1%' OR icd_code LIKE '714.2%' OR icd_code LIKE '714.8%'))
      OR (icd_version = 10 AND (icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M08%' OR icd_code LIKE 'M12%' OR icd_code LIKE 'M32%' OR icd_code LIKE 'M33%' OR icd_code LIKE 'M34%' OR icd_code LIKE 'M35%'))
    THEN 1 ELSE 0 END) AS connective,
    -- Peptic ulcer (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '531%' OR icd_code LIKE '532%' OR icd_code LIKE '533%' OR icd_code LIKE '534%'))
      OR (icd_version = 10 AND (icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%'))
    THEN 1 ELSE 0 END) AS ulcer,
    -- Mild liver (1)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '570%' OR icd_code LIKE '571.4%' OR icd_code LIKE '571.5%' OR icd_code LIKE '571.8%' OR icd_code LIKE '571.9%' OR icd_code LIKE '573.3%' OR icd_code LIKE '573.4%' OR icd_code LIKE '573.9%'))
      OR (icd_version = 10 AND (
        icd_code LIKE 'B18%' OR 
        (icd_code LIKE 'K70.0%' OR icd_code LIKE 'K70.1%' OR icd_code LIKE 'K70.2%' OR icd_code LIKE 'K70.3%') OR 
        icd_code LIKE 'K70.9%' OR 
        (icd_code LIKE 'K71.3%' OR icd_code LIKE 'K71.4%' OR icd_code LIKE 'K71.5%') OR 
        icd_code LIKE 'K71.7%' OR 
        icd_code LIKE 'K73%' OR 
        icd_code LIKE 'K74.6%' OR 
        icd_code LIKE 'K76.0%' OR 
        (icd_code LIKE 'K76.8%' OR icd_code LIKE 'K76.9%')
      ))
    THEN 1 ELSE 0 END) AS liver_mild,
    -- DM (1, simplified all types)
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '250%')
      OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'))
    THEN 1 ELSE 0 END) AS dm,
    -- Hemiplegia (2)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '342%' OR icd_code LIKE '343%' OR icd_code LIKE '344.0%' OR icd_code LIKE '344.1%' OR icd_code LIKE '344.2%' OR icd_code LIKE '344.3%' OR icd_code LIKE '344.4%' OR icd_code LIKE '344.5%' OR icd_code LIKE '344.9%'))
      OR (icd_version = 10 AND (icd_code LIKE 'G81%' OR icd_code LIKE 'G82%' OR icd_code = 'G83.0' OR icd_code = 'G83.1' OR icd_code = 'G83.2' OR icd_code = 'G83.4' OR icd_code LIKE 'G83.9%'))
    THEN 1 ELSE 0 END) AS hemiplegia,
    -- Renal (2)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '582%' OR icd_code LIKE '583%' OR icd_code LIKE '585%' OR icd_code LIKE '586%' OR icd_code LIKE '588%' OR icd_code = 'V42.0' OR icd_code LIKE 'V45.1%' OR icd_code LIKE 'V56%'))
      OR (icd_version = 10 AND (icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code = 'N25.1' OR icd_code LIKE 'Z49.0%' OR icd_code LIKE 'Z49.2%' OR icd_code = 'Z94.0' OR icd_code = 'Z99.2'))
    THEN 1 ELSE 0 END) AS renal,
    -- Cancer (2 or 3)
    MAX(CASE WHEN 
      -- Metastatic first (3)
      ((icd_version = 9 AND (icd_code LIKE '196%' OR icd_code LIKE '197%' OR icd_code LIKE '198%' OR icd_code LIKE '199%'))
      OR (icd_version = 10 AND (icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' OR icd_code LIKE 'C80%'))) THEN 3
      -- Solid/hematologic (2)
      WHEN 
      ((icd_version = 9 AND SAFE_CAST(SUBSTR(icd_code, 1, 3) AS NUMERIC) BETWEEN 140 AND 208)
      OR (icd_version = 10 AND icd_code LIKE 'C%')) THEN 2
      ELSE 0 END) AS cancer,
    -- Severe liver (2)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code = '456.0' OR icd_code = '456.2' OR icd_code LIKE '572.2%' OR icd_code LIKE '572.4%' OR icd_code LIKE '572.7%' OR icd_code LIKE '572.8%' OR icd_code = '456.1' OR icd_code LIKE '572.3%'))
      OR (icd_version = 10 AND (icd_code LIKE 'I85.0%' OR icd_code LIKE 'I85.1%' OR icd_code = 'I85.9' OR icd_code = 'I86.4' OR icd_code = 'I98.2' OR icd_code LIKE 'K70.4%' OR icd_code LIKE 'K72.1%' OR icd_code = 'K72.9' OR icd_code = 'K76.6' OR icd_code LIKE 'K76.7%' OR icd_code = 'R17' OR icd_code = 'R18'))
    THEN 1 ELSE 0 END) AS liver_severe,
    -- HIV (6)
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '042%' OR icd_code LIKE '043%' OR icd_code LIKE '044%'))
      OR (icd_version = 10 AND (icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B24%'))
    THEN 1 ELSE 0 END) AS hiv
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
final_data AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    CASE WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = c.hadm_id) THEN 'ICU' ELSE 'No ICU' END AS icu_flag,
    CASE 
      WHEN c.los_days <= 3 THEN '1-3'
      WHEN c.los_days <= 7 THEN '4-7'
      ELSE '>=8'
    END AS los_group,
    (COALESCE(cc.mi, 0) 
     + COALESCE(cc.chf, 0) 
     + COALESCE(cc.pvd, 0) 
     + COALESCE(cc.stroke, 0) 
     + COALESCE(cc.dementia, 0) 
     + COALESCE(cc.copd, 0) 
     + COALESCE(cc.connective, 0) 
     + COALESCE(cc.ulcer, 0) 
     + COALESCE(cc.liver_mild, 0) 
     + COALESCE(cc.dm, 0) 
     + 2 * COALESCE(cc.hemiplegia, 0) 
     + 2 * COALESCE(cc.renal, 0) 
     + COALESCE(cc.cancer, 0) 
     + 2 * COALESCE(cc.liver_severe, 0) 
     + 6 * COALESCE(cc.hiv, 0)) AS charlson_score,
    CASE 
      WHEN (COALESCE(cc.mi, 0) + COALESCE(cc.chf, 0) + COALESCE(cc.pvd, 0) + COALESCE(cc.stroke, 0) + COALESCE(cc.dementia, 0) + COALESCE(cc.copd, 0) + COALESCE(cc.connective, 0) + COALESCE(cc.ulcer, 0) + COALESCE(cc.liver_mild, 0) + COALESCE(cc.dm, 0) + 2 * COALESCE(cc.hemiplegia, 0) + 2 * COALESCE(cc.renal, 0) + COALESCE(cc.cancer, 0) + 2 * COALESCE(cc.liver_severe, 0) + 6 * COALESCE(cc.hiv, 0)) <= 3 THEN '<=3'
      WHEN (COALESCE(cc.mi, 0) + COALESCE(cc.chf, 0) + COALESCE(cc.pvd, 0) + COALESCE(cc.stroke, 0) + COALESCE(cc.dementia, 0) + COALESCE(cc.copd, 0) + COALESCE(cc.connective, 0) + COALESCE(cc.ulcer, 0) + COALESCE(cc.liver_mild, 0) + COALESCE(cc.dm, 0) + 2 * COALESCE(cc.hemiplegia, 0) + 2 * COALESCE(cc.renal, 0) + COALESCE(cc.cancer, 0) + 2 * COALESCE(cc.liver_severe, 0) + 6 * COALESCE(cc.hiv, 0)) <= 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group
  FROM cohort c
  LEFT JOIN charlson_comps cc ON c.hadm_id = cc.hadm_id
)
SELECT 
  icu_flag,
  los_group,
  charlson_group,
  COUNT(*) AS total,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  ROUND(100.0 * (p - 1.96 * SQRT(p * (1 - p) / total_n)), 2) AS ci_lower_pct,
  ROUND(100.0 * (p + 1.96 * SQRT(p * (1 - p) / total_n)), 2) AS ci_upper_pct,
  ROUND(AVG(charlson_score), 2) AS mean_comorbidity_count
FROM (
  SELECT 
    icu_flag,
    los_group,
    CASE WHEN charlson_score <= 3 THEN '<=3'
         WHEN charlson_score <= 5 THEN '4-5'
         ELSE '>5'
    END AS charlson_group,
    hospital_expire_flag,
    charlson_score,
    COUNT(*) OVER (PARTITION BY icu_flag, los_group, CASE WHEN charlson_score <= 3 THEN '<=3' WHEN charlson_score <= 5 THEN '4-5' ELSE '>5' END) AS total_n,
    SUM(hospital_expire_flag) OVER (PARTITION BY icu_flag, los_group, CASE WHEN charlson_score <= 3 THEN '<=3' WHEN charlson_score <= 5 THEN '4-5' ELSE '>5' END) * 1.0 / COUNT(*) OVER (PARTITION BY icu_flag, los_group, CASE WHEN charlson_score <= 3 THEN '<=3' WHEN charlson_score <= 5 THEN '4-5' ELSE '>5' END) AS p
  FROM final_data
)
GROUP BY icu_flag, los_group, charlson_group, total_n, p
ORDER BY icu_flag, los_group, charlson_group;