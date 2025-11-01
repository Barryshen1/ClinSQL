WITH cohort AS (
  -- Get first ICU stay for each admission with upper GI bleeding
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
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND (
      (d.icd_version = 10 AND d.icd_code IN ('K920', 'K921', 'K922')) OR
      (d.icd_version = 9 AND d.icd_code LIKE '578%')
    )
    -- Get first ICU stay per admission
    AND i.intime = (
      SELECT MIN(i2.intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i2
      WHERE i2.hadm_id = a.hadm_id
    )
),
procedures_icd_72h AS (
  -- Count ICD procedures in first 72h of ICU
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT p.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
  WHERE 
    -- Procedures within first 72h of ICU stay
    (p.chartdate BETWEEN DATETIME_SUB(c.intime, INTERVAL 72 HOUR) AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    OR pe.starttime BETWEEN DATETIME_SUB(c.intime, INTERVAL 72 HOUR) AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR))
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
procedureevents_72h AS (
  -- Count ICU procedures in first 72h
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
  WHERE 
    pe.starttime BETWEEN DATETIME_SUB(c.intime, INTERVAL 72 HOUR) AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
combined_procedures AS (
  -- Combine counts from both sources
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COALESCE(picd.proc_count, 0) + COALESCE(pev.proc_count, 0) AS total_proc_count
  FROM cohort c
  LEFT JOIN procedures_icd_72h picd
    ON c.stay_id = picd.stay_id
  LEFT JOIN procedureevents_72h pev
    ON c.stay_id = pev.stay_id
),
quartiles AS (
  -- Assign quartiles based on total_proc_count
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    total_proc_count,
    NTILE(4) OVER (ORDER BY total_proc_count) AS quartile
  FROM combined_procedures
)
-- Final aggregation
SELECT 
  q.quartile,
  COUNT(*) AS num_patients,
  AVG(q.total_proc_count) AS mean_procedure_count,
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS mean_hospital_los_days,
  AVG(CAST(a.hospital_expire_flag AS INT)) * 100 AS in_hospital_mortality_percent
FROM quartiles q
INNER JOIN cohort c
  ON q.stay_id = c.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON c.hadm_id = a.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;