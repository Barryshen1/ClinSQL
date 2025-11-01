WITH qualifying_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),
first_icustays AS (
  SELECT
    hadm_id,
    stay_id,
    intime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort AS (
  SELECT
    qa.*,
    fis.stay_id,
    fis.intime
  FROM qualifying_admissions qa
  INNER JOIN first_icustays fis
    ON qa.hadm_id = fis.hadm_id AND fis.rn = 1
),
procedure_counts AS (
  SELECT
    c.stay_id,
    COUNT(pe.stay_id) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id
),
cohort_with_procs AS (
  SELECT
    c.*,
    COALESCE(pc.proc_count, 0) AS proc_count
  FROM cohort c
  LEFT JOIN procedure_counts pc
    ON c.stay_id = pc.stay_id
)
SELECT
  quartile,
  COUNT(*) AS n,
  AVG(proc_count) AS mean_procedure_count,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_hospital_los_days,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS in_hospital_mortality_pct
FROM (
  SELECT *,
    NTILE(4) OVER (ORDER BY proc_count ASC) AS quartile
  FROM cohort_with_procs
)
GROUP BY quartile
ORDER BY quartile;