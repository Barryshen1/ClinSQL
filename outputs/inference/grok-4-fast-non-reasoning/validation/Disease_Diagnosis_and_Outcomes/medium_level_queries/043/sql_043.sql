WITH cohort AS (
  -- Base cohort: males 44-54 with HF admission
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (p.dod > a.admittime OR p.dod IS NULL)  -- Exclude pre-admission deaths
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%heart failure%'
    )
),

icu_flag AS (
  -- Flag ICU admission
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
      ) THEN 1 ELSE 0 
    END AS icu_admission
  FROM cohort c
),

los_bin AS (
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE WHEN DATE_DIFF(dischtime, admittime, DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_bin
  FROM icu_flag
),

charlson_comorbidities AS (
  -- Simplified Charlson flags (Deyo adaptation)
  SELECT 
    l.hadm_id,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%myocardial infarction%' THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%peripheral vascular disease%' OR LOWER(TRIM(di.long_title)) LIKE '%arterial embolism%' THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%cerebrovascular%' OR LOWER(TRIM(di.long_title)) LIKE '%stroke%' THEN 1 ELSE 0 END) AS cvd,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%dementia%' THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%chronic obstructive pulmonary%' THEN 1 ELSE 0 END) AS copd,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%rheumatoid arthritis%' OR LOWER(TRIM(di.long_title)) LIKE '%systemic lupus%' THEN 1 ELSE 0 END) AS ctd,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%peptic ulcer%' THEN 1 ELSE 0 END) AS ulcer,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%chronic liver disease%' AND LOWER(TRIM(di.long_title)) NOT LIKE '%cirrhosis%' THEN 1 ELSE 0 END) AS mild_liver,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%diabetes mellitus%' AND LOWER(TRIM(di.long_title)) NOT LIKE '%complication%' THEN 1 ELSE 0 END) AS dm,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%paraplegia%' OR LOWER(TRIM(di.long_title)) LIKE '%hemiplegia%' THEN 1 ELSE 0 END) AS hemiplegia,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%renal failure%' OR LOWER(TRIM(di.long_title)) LIKE '%dialysis%' THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%diabetes mellitus%' AND LOWER(TRIM(di.long_title)) LIKE '%complication%' THEN 1 ELSE 0 END) AS dm_comp,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%malignant neoplasm%' AND LOWER(TRIM(di.long_title)) NOT LIKE '%skin%' THEN 1 ELSE 0 END) AS malignancy,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%cirrhosis%' THEN 1 ELSE 0 END) AS mod_liver,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%metastatic%' OR LOWER(TRIM(di.long_title)) LIKE '%secondary neoplasm%' THEN 1 ELSE 0 END) AS met_cancer,
    MAX(CASE WHEN LOWER(TRIM(di.long_title)) LIKE '%hiv%' OR LOWER(TRIM(di.long_title)) LIKE '%aids%' THEN 1 ELSE 0 END) AS aids
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON l.icd_code = di.icd_code AND l.icd_version = di.icd_version
  GROUP BY l.hadm_id
),

charlson_score AS (
  SELECT 
    lb.*,
    COALESCE(cc.mi, 0) * 1 + COALESCE(cc.chf, 0) * 1 + COALESCE(cc.pvd, 0) * 1 + 
    COALESCE(cc.cvd, 0) * 1 + COALESCE(cc.dementia, 0) * 1 + COALESCE(cc.copd, 0) * 1 + 
    COALESCE(cc.ctd, 0) * 1 + COALESCE(cc.ulcer, 0) * 1 + COALESCE(cc.mild_liver, 0) * 1 + 
    COALESCE(cc.dm, 0) * 1 + COALESCE(cc.hemiplegia, 0) * 1 + COALESCE(cc.renal, 0) * 2 + 
    COALESCE(cc.dm_comp, 0) * 2 + COALESCE(cc.malignancy, 0) * 2 + COALESCE(cc.mod_liver, 0) * 2 + 
    COALESCE(cc.met_cancer, 0) * 6 + COALESCE(cc.aids, 0) * 6 AS charlson_raw,
    CASE 
      WHEN (COALESCE(cc.mi, 0) * 1 + COALESCE(cc.chf, 0) * 1 + COALESCE(cc.pvd, 0) * 1 + 
            COALESCE(cc.cvd, 0) * 1 + COALESCE(cc.dementia, 0) * 1 + COALESCE(cc.copd, 0) * 1 + 
            COALESCE(cc.ctd, 0) * 1 + COALESCE(cc.ulcer, 0) * 1 + COALESCE(cc.mild_liver, 0) * 1 + 
            COALESCE(cc.dm, 0) * 1 + COALESCE(cc.hemiplegia, 0) * 1 + COALESCE(cc.renal, 0) * 2 + 
            COALESCE(cc.dm_comp, 0) * 2 + COALESCE(cc.malignancy, 0) * 2 + COALESCE(cc.mod_liver, 0) * 2 + 
            COALESCE(cc.met_cancer, 0) * 6 + COALESCE(cc.aids, 0) * 6) <= 1 THEN '0-1'
      WHEN (COALESCE(cc.mi, 0) * 1 + COALESCE(cc.chf, 0) * 1 + COALESCE(cc.pvd, 0) * 1 + 
            COALESCE(cc.cvd, 0) * 1 + COALESCE(cc.dementia, 0) * 1 + COALESCE(cc.copd, 0) * 1 + 
            COALESCE(cc.ctd, 0) * 1 + COALESCE(cc.ulcer, 0) * 1 + COALESCE(cc.mild_liver, 0) * 1 + 
            COALESCE(cc.dm, 0) * 1 + COALESCE(cc.hemiplegia, 0) * 1 + COALESCE(cc.renal, 0) * 2 + 
            COALESCE(cc.dm_comp, 0) * 2 + COALESCE(cc.malignancy, 0) * 2 + COALESCE(cc.mod_liver, 0) * 2 + 
            COALESCE(cc.met_cancer, 0) * 6 + COALESCE(cc.aids, 0) * 6) = 2 THEN '2'
      ELSE '>=3'
    END AS charlson_bin
  FROM los_bin lb
  LEFT JOIN charlson_comorbidities cc ON lb.hadm_id = cc.hadm_id
),

outcomes AS (
  SELECT 
    cs.subject_id,
    cs.hadm_id,
    cs.icu_admission,
    cs.los_bin,
    cs.charlson_bin,
    cs.hospital_expire_flag,
    -- Mech vent: any ventilation procedure in ICU stay
    CASE 
      WHEN cs.icu_admission = 0 THEN 0
      ELSE MAX(CASE WHEN pe.itemid IN (225477, 225468, 225789, 220339, 227128)
                    AND pe.starttime BETWEEN i.intime AND i.outtime THEN 1 ELSE 0 END)
    END AS mech_vent,
    -- Vasopressors: any relevant input in ICU stay
    CASE 
      WHEN cs.icu_admission = 0 THEN 0
      ELSE MAX(CASE WHEN ie.itemid IN (220615, 220606, 220452, 221906, 30047, 30120, 30307, 220509)
                    AND ie.rate > 0 AND ie.starttime BETWEEN i.intime AND i.outtime THEN 1 ELSE 0 END)
    END AS vasopressor,
    -- RRT: any renal replacement therapy in ICU stay
    CASE 
      WHEN cs.icu_admission = 0 THEN 0
      ELSE MAX(CASE WHEN (ie.itemid IN (225798, 225800, 225843) OR pe.itemid IN (225456))
                    AND (ie.starttime BETWEEN i.intime AND i.outtime OR pe.starttime BETWEEN i.intime AND i.outtime) THEN 1 ELSE 0 END)
    END AS rrt,
    MAX(i.intime) AS max_intime,
    MAX(i.outtime) AS max_outtime
  FROM charlson_score cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON cs.subject_id = i.subject_id AND cs.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON i.stay_id = pe.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON i.stay_id = ie.stay_id
  GROUP BY cs.subject_id, cs.hadm_id, cs.icu_admission, cs.los_bin, cs.charlson_bin, cs.hospital_expire_flag
)

-- Aggregate results
SELECT 
  icu_admission,
  los_bin,
  charlson_bin,
  COUNT(*) AS n,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct,
  -- 95% CI for mortality (Wilson score approximation)
  ROUND(100 * (p + z2/(2*n) - z * SQRT((p*(1-p)/n + z2/(4*n*n))) / (1 + z2/n)), 2) AS ci_lower,
  ROUND(100 * (p + z2/(2*n) + z * SQRT((p*(1-p)/n + z2/(4*n*n))) / (1 + z2/n)), 2) AS ci_upper,
  ROUND(SUM(mech_vent) * 100.0 / COUNT(*), 2) AS mech_vent_pct,
  ROUND(SUM(vasopressor) * 100.0 / COUNT(*), 2) AS vasopressor_pct,
  ROUND(SUM(rrt) * 100.0 / COUNT(*), 2) AS rrt_pct
FROM (
  SELECT 
    *,
    SUM(hospital_expire_flag) * 1.0 / COUNT(*) OVER (PARTITION BY icu_admission, los_bin, charlson_bin) AS p,
    1.96 AS z,
    POW(1.96, 2) AS z2,
    COUNT(*) OVER (PARTITION BY icu_admission, los_bin, charlson_bin) AS n
  FROM outcomes
) 
GROUP BY icu_admission, los_bin, charlson_bin, p, z, z2, n
HAVING n > 0  -- Exclude empty groups
ORDER BY icu_admission, los_bin, charlson_bin;