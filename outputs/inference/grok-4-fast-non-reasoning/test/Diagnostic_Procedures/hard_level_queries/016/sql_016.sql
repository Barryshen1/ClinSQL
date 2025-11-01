WITH eligible_stays AS (
  -- Base cohort: first ICU stays for male patients aged 88-98 with primary pneumonia dx
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn_first_stay
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.seq_num = 1
    AND d.icd_code LIKE '48%'
    AND icd.long_title LIKE '%pneumonia%'
),
first_stays AS (
  SELECT *
  FROM eligible_stays
  WHERE rn_first_stay = 1
),
procedure_counts AS (
  -- Count distinct diagnostic procedures in first 72 hours
  SELECT 
    fs.stay_id,
    fs.hadm_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM first_stays fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fs.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE (pe.starttime BETWEEN fs.intime AND TIMESTAMP_ADD(fs.intime, INTERVAL 72 HOUR)
      OR pe.endtime BETWEEN fs.intime AND TIMESTAMP_ADD(fs.intime, INTERVAL 72 HOUR))
    AND (di.category LIKE '%Diagnostic%' 
         OR di.label LIKE '%X-Ray%' 
         OR di.label LIKE '%CT%' 
         OR di.label LIKE '%MRI%' 
         OR di.label LIKE '%Ultrasound%' 
         OR di.label LIKE '%Biopsy%' 
         OR di.label LIKE '%Endoscopy%')
    AND pe.itemid IS NOT NULL  -- Exclude invalid
  GROUP BY fs.stay_id, fs.hadm_id
),
stay_metrics AS (
  SELECT 
    fs.*,
    COALESCE(pc.num_procedures, 0) AS num_procedures,
    NTILE(5) OVER (ORDER BY COALESCE(pc.num_procedures, 0)) AS quintile
  FROM first_stays fs
  LEFT JOIN procedure_counts pc
    ON fs.stay_id = pc.stay_id
)
SELECT 
  quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(num_procedures), 2) AS avg_procedure_count,
  ROUND(AVG(los / 24.0), 2) AS avg_icu_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct
FROM stay_metrics
GROUP BY quintile
ORDER BY quintile;