WITH ami_hadm AS (
  -- admissions for female patients age 44-54 that have an AMI diagnosis
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      LOWER(COALESCE(d.long_title, '')) LIKE '%acute myocardial%'
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%acute mi%'
      OR di.icd_code LIKE '410%'   -- ICD-9 AMI
      OR di.icd_code LIKE 'I21%'   -- ICD-10 AMI
    )
),

first_icustay AS (
  -- pick the first ICU stay for each hadm_id (within the admissions with AMI)
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY s.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` s
    WHERE s.hadm_id IS NOT NULL
  ) s
  WHERE s.rn = 1
    AND s.hadm_id IN (SELECT hadm_id FROM ami_hadm)
),

proc_counts_72h AS (
  -- correlated count per first ICU stay constrained to 72 hours
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE((
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = f.stay_id
        AND pe.starttime IS NOT NULL
        AND pe.starttime >= f.intime
        AND pe.starttime <= TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
    ), 0) AS proc_count
  FROM first_icustay f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.hadm_id = a.hadm_id
),

quartiled AS (
  -- assign quartiles based on proc_count distribution
  SELECT
    pc.*,
    NTILE(4) OVER (ORDER BY pc.proc_count) AS quartile
  FROM proc_counts_72h pc
)

-- final aggregation per quartile
SELECT
  quartile,
  COUNT(1) AS n_patients,
  ROUND(AVG(proc_count), 2) AS mean_procedure_count,
  -- mean hospital LOS in days
  ROUND(AVG(
    CASE
      WHEN admittime IS NOT NULL AND dischtime IS NOT NULL
        THEN TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0
      ELSE NULL
    END
  ), 2) AS mean_hospital_los_days,
  -- in-hospital mortality percent
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(1), 2) AS in_hospital_mortality_pct
FROM quartiled
GROUP BY quartile
ORDER BY quartile;