WITH pe_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    adm.hadm_id, 
    adm.admittime, 
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('4151', '41511', '41519')) 
      OR 
      (diag.icd_version = 10 AND diag.icd_code IN ('I26', 'I260', 'I269'))
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 65 AND 75
),
first_icu_stay AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id, 
    icu.intime, 
    icu.outtime, 
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN pe_patients pat
    ON icu.hadm_id = pat.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) = 1
),
procedure_counts AS (
  SELECT 
    icu.stay_id,
    COUNT(proc.itemid) AS procedure_count
  FROM first_icu_stay icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON icu.stay_id = proc.stay_id
    AND proc.starttime BETWEEN icu.intime 
        AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON proc.itemid = di.itemid
    AND REGEXP_CONTAINS(di.category, r'Diagnostic|Imaging|Radiology')
  GROUP BY icu.stay_id
),
quartile_data AS (
  SELECT 
    icu.stay_id,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    icu.los,
    pat.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY COALESCE(pc.procedure_count, 0)) AS quartile
  FROM first_icu_stay icu
  LEFT JOIN procedure_counts pc
    ON icu.stay_id = pc.stay_id
  INNER JOIN pe_patients pat
    ON icu.hadm_id = pat.hadm_id
)
SELECT 
  quartile,
  COUNT(stay_id) AS N,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS hospital_mortality_percent
FROM quartile_data
GROUP BY quartile
ORDER BY quartile;