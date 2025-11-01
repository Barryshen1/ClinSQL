WITH first_icu_stays AS (
  SELECT 
    subject_id, hadm_id, stay_id, first_careunit, last_careunit, 
    intime, outtime, los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE intime IS NOT NULL
),
eligible_patients AS (
  SELECT DISTINCT 
    fis.subject_id, fis.hadm_id, fis.stay_id, fis.intime, fis.outtime, fis.los,
    adm.hospital_expire_flag
  FROM first_icu_stays fis
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON fis.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON fis.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON fis.subject_id = diag.subject_id AND fis.hadm_id = diag.hadm_id
  WHERE fis.rn = 1
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND (diag.icd_code LIKE '57.%' OR diag.icd_code LIKE 'K7%')  -- Hepatic failure/cirrhosis
),
procedure_counts AS (
  SELECT 
    ep.*,
    COUNT(DISTINCT proc.icd_code) AS procedure_count
  FROM eligible_patients ep
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON ep.subject_id = proc.subject_id 
    AND ep.hadm_id = proc.hadm_id
    AND DATE(proc.chartdate) >= ep.intime
    AND DATE(proc.chartdate) < TIMESTAMP_ADD(ep.intime, INTERVAL 72 HOUR)
  GROUP BY 
    ep.subject_id, ep.hadm_id, ep.stay_id, ep.intime, ep.outtime, ep.los, 
    ep.hospital_expire_flag
),
with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM procedure_counts
)
SELECT 
  quartile,
  COUNT(DISTINCT subject_id) AS num_patients,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  ROUND(AVG(procedure_count), 2) AS mean_procedures,
  ROUND(AVG(los / 86400.0), 2) AS mean_los_days,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 1) AS mortality_pct
FROM with_quartiles
GROUP BY quartile
ORDER BY quartile;