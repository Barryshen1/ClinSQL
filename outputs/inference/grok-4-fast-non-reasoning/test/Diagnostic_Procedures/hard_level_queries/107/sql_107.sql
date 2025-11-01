WITH pe_cohort AS (
  -- Base cohort: female, 65-75, first ICU stay, with primary PE diagnosis
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    i.first_careunit,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND d.seq_num = 1
    AND (
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I26%') OR
      (d.icd_version = 'ICD-9' AND (d.icd_code = '415.1' OR d.icd_code LIKE '415.1%'))
    )
    AND icd.long_title LIKE '%embolism%'  -- Ensure PE-specific
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) = 1
),
procedure_counts AS (
  -- Count distinct diagnostic procedure itemids within 72h of ICU intime using ICU procedureevents
  SELECT 
    pc.*,
    COUNT(DISTINCT pr.itemid) AS procedure_count
  FROM 
    pe_cohort pc
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pr
    ON pc.stay_id = pr.stay_id
    AND pr.starttime BETWEEN pc.intime AND pc.intime + INTERVAL 72 HOUR
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON CAST(pr.itemid AS STRING) = di.itemid
    AND (di.category LIKE '%Diagnostic%' OR di.label LIKE '%Imaging%' OR di.label LIKE '%Echo%' OR di.label LIKE '%CT%' OR di.label LIKE '%MRI%')
  GROUP BY 
    pc.subject_id, pc.stay_id, pc.hadm_id, pc.intime, pc.los, pc.first_careunit, 
    pc.gender, pc.anchor_age, pc.hospital_expire_flag
),
stratified AS (
  -- Assign quartiles and aggregate
  SELECT 
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile,
    COUNT(*) AS n,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los / 24.0) AS mean_los_days,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100 AS mortality_pct
  FROM 
    procedure_counts
  GROUP BY 
    quartile
)
SELECT 
  quartile,
  n,
  ROUND(mean_procedure_count, 2) AS mean_procedure_count,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mortality_pct, 2) AS mortality_pct
FROM 
  stratified
ORDER BY 
  quartile;