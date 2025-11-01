WITH first_icu_stays AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    p.anchor_age,
    p.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- Calculate hospital LOS in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hosp_los_days,
    -- Identify sepsis: has sepsis ICD code (ICD-9: 995.91, 995.92; ICD-10: R65.20, R65.21)
    MAX(CASE 
        WHEN di.icd_code IN ('99591','99592') AND di.icd_version = 9 THEN 1
        WHEN di.icd_code IN ('R6520','R6521') AND di.icd_version = 10 THEN 1
        ELSE 0 
    END) AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ie.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, p.anchor_age, p.gender, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  -- Keep only the first ICU stay per subject
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) = 1
),

-- Count distinct procedures in first 48h for each stay (using procedureevents)
procedure_counts AS (
  SELECT 
    fis.subject_id,
    fis.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fis.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN fis.intime AND DATETIME_ADD(fis.intime, INTERVAL 48 HOUR)
  GROUP BY fis.subject_id, fis.stay_id
)

-- Main query: for sepsis cases, get the 90th percentile of procedure count, and compare LOS and mortality with controls
SELECT 
  'Sepsis' AS cohort,
  COUNT(*) AS n_patients,
  -- 90th percentile of distinct procedures for sepsis cases
  APPROX_QUANTILES(pc.num_procedures, 100)[OFFSET(90)] AS proc_90th_percentile,
  AVG(fis.hosp_los_days) AS avg_hosp_los,
  AVG(fis.hospital_expire_flag) AS mortality_rate
FROM first_icu_stays fis
LEFT JOIN procedure_counts pc
  ON fis.subject_id = pc.subject_id AND fis.stay_id = pc.stay_id
WHERE fis.has_sepsis = 1
GROUP BY cohort

UNION ALL

SELECT 
  'Control' AS cohort,
  COUNT(*) AS n_patients,
  NULL AS proc_90th_percentile,  -- Not applicable for controls
  AVG(fis.hosp_los_days) AS avg_hosp_los,
  AVG(fis.hospital_expire_flag) AS mortality_rate
FROM first_icu_stays fis
WHERE fis.has_sepsis = 0
GROUP BY cohort;