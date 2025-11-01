WITH asthma_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%asthma%' 
    AND (LOWER(long_title) LIKE '%exacerbation%' OR LOWER(long_title) LIKE '%acute%')
    AND icd_version = 10
),
asthma_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN asthma_codes ac ON di.icd_code = ac.icd_code AND di.icd_version = 10
  WHERE di.seq_num = 1  -- primary diagnosis
  GROUP BY di.hadm_id
),
patient_icu_stays AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600.0) AS hosp_los_days,
    -- Adjust age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN asthma_admissions aa ON a.hadm_id = aa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND i.intime IS NOT NULL
    AND i.intime >= a.admittime  -- valid ICU stay
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),
procedure_counts AS (
  SELECT 
    pis.subject_id,
    pis.hadm_id,
    pis.stay_id,
    COUNT(pe.stay_id) AS procedure_count_72h,
    pis.hosp_los_days,
    pis.hospital_expire_flag
  FROM patient_icu_stays pis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON pis.stay_id = pe.stay_id
    AND pe.starttime >= pis.intime 
    AND pe.starttime <= DATETIME_ADD(pis.intime, INTERVAL 72 HOUR)
  GROUP BY pis.subject_id, pis.hadm_id, pis.stay_id, pis.hosp_los_days, pis.hospital_expire_flag
),
quartiles AS (
  SELECT 
    procedure_count_72h,
    hosp_los_days,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY procedure_count_72h) AS quartile
  FROM procedure_counts
  WHERE procedure_count_72h IS NOT NULL
)
SELECT 
  quartile,
  AVG(procedure_count_72h) AS mean_procedure_count,
  AVG(hosp_los_days) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM quartiles
GROUP BY quartile
ORDER BY quartile;