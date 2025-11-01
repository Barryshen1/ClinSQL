WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    -- Calculate hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.seq_num = 1  -- primary diagnosis
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'J45%') OR
      (d.icd_version = 9 AND d.icd_code LIKE '493%')
    )
),

procedures_in_first_72h AS (
  SELECT 
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.subject_id = pe.subject_id 
    AND c.hadm_id = pe.hadm_id 
    AND c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id
),

cohort_with_procedures AS (
  SELECT 
    c.*,
    COALESCE(p.procedure_count, 0) AS procedure_count
  FROM cohort c
  LEFT JOIN procedures_in_first_72h p
    ON c.stay_id = p.stay_id
),

quartiles AS (
  SELECT 
    stay_id,
    procedure_count,
    los_days,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM cohort_with_procedures
)

SELECT 
  quartile,
  COUNT(*) AS n_stays,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM quartiles
GROUP BY quartile
ORDER BY quartile;