WITH cohort AS (
  -- Base cohort: male patients aged 66-76 with ICU stays and HHS diagnosis
  SELECT DISTINCT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON CAST(i.hadm_id AS STRING) = CAST(d.hadm_id AS STRING)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND d.icd_version = '10'
    AND (d.icd_code = 'E131' OR d.icd_code = 'E132')
),
procedure_burden AS (
  -- Calculate procedure events within 48 hours per ICU stay (itemid < 220000 for actual procedures)
  SELECT 
    c.*,
    COUNT(*) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.subject_id = pe.subject_id
    AND CAST(c.hadm_id AS STRING) = CAST(pe.hadm_id AS STRING)
    AND c.stay_id = pe.stay_id
    AND pe.itemid < 220000
    AND pe.starttime >= c.intime
    AND pe.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY 
    c.subject_id, c.stay_id, c.hadm_id, c.intime, c.dischtime, c.hospital_expire_flag
),
los_calc AS (
  -- Calculate hospital LOS (days)
  SELECT 
    *,
    DATE_DIFF(DATE(dischtime), DATE(intime), DAY) AS hosp_los_days
  FROM procedure_burden
),
next_adm AS (
  -- Get next admission details for readmission calculation
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
readmissions AS (
  -- Flag 30-day readmissions using next admission
  SELECT 
    l.*,
    CASE 
      WHEN na.next_admittime IS NOT NULL 
           AND DATE_DIFF(DATE(na.next_admittime), DATE(l.dischtime), DAY) <= 30
      THEN 1 
      ELSE 0 
    END AS readmit_30d
  FROM los_calc l
  LEFT JOIN next_adm na
    ON l.subject_id = na.subject_id
    AND l.hadm_id = na.hadm_id  -- Match on current hadm_id to get its next admission
)
SELECT 
  quintile,
  COUNT(stay_id) AS num_icu_stays,
  ROUND(AVG(procedure_count), 2) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_pct,
  ROUND(AVG(hosp_los_days), 2) AS mean_hosp_los_days,
  ROUND(AVG(readmit_30d) * 100, 2) AS readmission_30d_pct
FROM (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM readmissions
)
GROUP BY quintile
ORDER BY quintile;