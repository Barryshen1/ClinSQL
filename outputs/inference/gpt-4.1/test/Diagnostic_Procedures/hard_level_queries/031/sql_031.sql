WITH hhs_icd_codes AS (
  -- ICD-10 E11.0, ICD-9 250.2x
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 10 AND icd_code LIKE 'E11.0%')
    OR (icd_version = 9 AND (icd_code LIKE '250.20%' OR icd_code LIKE '250.21%' OR icd_code LIKE '250.22%' OR icd_code LIKE '250.23%'))
),
hhs_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN hhs_icd_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
),
cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN hhs_admissions h
    ON i.subject_id = h.subject_id AND i.hadm_id = h.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
),
procedures_48h AS (
  SELECT
    c.stay_id,
    COUNT(*) AS procedure_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE
    p.chartdate >= c.intime
    AND p.chartdate < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
cohort_with_proc AS (
  SELECT
    c.*,
    COALESCE(p48.procedure_count, 0) AS procedure_count
  FROM cohort c
  LEFT JOIN procedures_48h p48
    ON c.stay_id = p48.stay_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM cohort_with_proc
),
readmissions AS (
  -- For each discharge, find next admission within 30 days (exclude if died in hospital)
  SELECT
    q.stay_id,
    CASE
      WHEN q.hospital_expire_flag = 1 THEN 0
      ELSE
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE
              a2.subject_id = q.subject_id
              AND a2.admittime > q.dischtime
              AND a2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
          ) THEN 1
          ELSE 0
        END
    END AS readmit_30d
  FROM quintiles q
)
SELECT
  quintile,
  COUNT(*) AS num_icu_stays,
  ROUND(AVG(procedure_count),2) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS hospital_mortality_pct,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24),2) AS mean_hospital_los_days,
  ROUND(100.0 * AVG(readmit_30d),2) AS readmission_30d_pct
FROM (
  SELECT
    q.*,
    r.readmit_30d
  FROM quintiles q
  LEFT JOIN readmissions r
    ON q.stay_id = r.stay_id
)
GROUP BY quintile
ORDER BY quintile;