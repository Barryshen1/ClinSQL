WITH eligible AS (
  -- Select female patients aged 44-54 at admission who have AMI (I21/I22) in the same admission
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag AS death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')
    )
),
first_icu AS (
  -- Identify the first ICU stay for each admission
  SELECT s.subject_id,
         s.hadm_id,
         s.stay_id,
         s.intime
  FROM (
    SELECT subject_id,
           hadm_id,
           stay_id,
           intime,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) s
  WHERE s.rn = 1
),
proc_counts AS (
  -- Count procedure events within the first 72 hours of the first ICU stay
  SELECT e.subject_id,
         e.hadm_id,
         COUNT(pe.starttime) AS proc_count
  FROM eligible e
  JOIN first_icu f
    ON e.subject_id = f.subject_id
   AND e.hadm_id = f.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = f.subject_id
   AND pe.hadm_id = f.hadm_id
   AND pe.stay_id = f.stay_id
   AND pe.starttime BETWEEN f.intime
                         AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY e.subject_id, e.hadm_id
),
base AS (
  -- Bring togetherPROC count with LOS and mortality for quartile computation
  SELECT e.subject_id,
         e.hadm_id,
         pc.proc_count,
         (TIMESTAMP_DIFF(e.dischtime, e.admittime, SECOND) / 86400.0) AS los_days,
         e.death
  FROM eligible e
  JOIN proc_counts pc
    ON e.subject_id = pc.subject_id
   AND e.hadm_id = pc.hadm_id
),
quartiled AS (
  -- Assign quartiles based on procedure burden
  SELECT b.*,
         NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM base b
)
SELECT quartile,
       COUNT(*) AS n,
       AVG(proc_count) AS mean_procedure_count,
       AVG(los_days) AS mean_los_days,
       AVG(death) * 100 AS in_hospital_mortality_pct
FROM quartiled
GROUP BY quartile
ORDER BY quartile;