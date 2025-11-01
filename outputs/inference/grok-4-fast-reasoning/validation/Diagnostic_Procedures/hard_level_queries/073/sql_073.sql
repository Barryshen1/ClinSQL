WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      intime, 
      outtime, 
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON p.subject_id = i.subject_id AND i.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 90
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id 
        AND d.hadm_id = i.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'K72%'
    )
),
procs AS (
  SELECT 
    c.*,
    COUNT(DISTINCT l.itemid) AS num_diagnostic_procs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` l 
    ON l.subject_id = c.subject_id
    AND l.stay_id = c.stay_id
    AND l.starttime >= c.intime
    AND l.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY 
    c.subject_id, 
    c.anchor_age, 
    c.stay_id, 
    c.hadm_id, 
    c.intime, 
    c.outtime, 
    c.icu_los,
    c.admittime, 
    c.dischtime, 
    c.hospital_expire_flag
),
with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY num_diagnostic_procs) AS quartile
  FROM procs
)
SELECT 
  quartile,
  COUNT(*) AS num_patients,
  MIN(num_diagnostic_procs) AS min_procs,
  MAX(num_diagnostic_procs) AS max_procs,
  AVG(num_diagnostic_procs) AS mean_procs,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct
FROM with_quartiles
GROUP BY quartile
ORDER BY quartile;