WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
icustays AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
admissions AS (
  SELECT hadm_id, admittime, dischtime, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
base_cohort AS (
  SELECT p.subject_id, p.anchor_age, i.hadm_id, i.stay_id, i.intime,
         a.admittime, a.dischtime, a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM patients p
  INNER JOIN icustays i ON p.subject_id = i.subject_id
  INNER JOIN admissions a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 42 AND 52
),
first_stays AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
  FROM base_cohort
),
first_cohort AS (
  SELECT subject_id, hadm_id, stay_id, intime, admittime, dischtime,
         hospital_expire_flag, los_days
  FROM first_stays
  WHERE rn = 1
),
ami_first_cohort AS (
  SELECT fc.*
  FROM first_cohort fc
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE diag.subject_id = fc.subject_id
      AND diag.hadm_id = fc.hadm_id
      AND (
        (diag.icd_version = 9 AND diag.icd_code BETWEEN '41000' AND '41099')
        OR
        (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
      )
  )
),
ami_procedures AS (
  SELECT afc.subject_id,
         COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM ami_first_cohort afc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = afc.stay_id
    AND pe.starttime >= afc.intime
    AND pe.starttime < TIMESTAMP_ADD(afc.intime, INTERVAL 72 HOUR)
  GROUP BY afc.subject_id
),
ami_metrics AS (
  SELECT
    APPROX_QUANTILES(ap.num_procedures, 100)[OFFSET(90)] AS p90_procedures,
    AVG(afc.los_days) AS mean_los_ami,
    AVG(afc.hospital_expire_flag * 1.0) AS mortality_ami
  FROM ami_procedures ap
  INNER JOIN ami_first_cohort afc ON ap.subject_id = afc.subject_id
),
all_metrics AS (
  SELECT
    AVG(fc.los_days) AS mean_los_all,
    AVG(fc.hospital_expire_flag * 1.0) AS mortality_all
  FROM first_cohort fc
)
SELECT
  p90_procedures,
  mean_los_ami,
  mortality_ami,
  mean_los_all,
  mortality_all
FROM ami_metrics, all_metrics;