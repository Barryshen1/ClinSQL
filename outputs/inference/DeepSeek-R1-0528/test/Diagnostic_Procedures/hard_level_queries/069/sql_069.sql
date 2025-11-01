WITH pe_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'M'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '4151%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I26%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),

first_icu_stay AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN pe_patients pp
    ON icu.hadm_id = pp.hadm_id
),

cohort AS (
  SELECT
    pp.*,
    icu.stay_id,
    icu.intime
  FROM pe_patients pp
  INNER JOIN first_icu_stay icu
    ON pp.hadm_id = icu.hadm_id
    AND pp.subject_id = icu.subject_id
    AND icu.stay_rank = 1
),

procedure_counts AS (
  SELECT
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id
),

cohort_with_counts AS (
  SELECT
    c.*,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS hospital_los
  FROM cohort c
  LEFT JOIN procedure_counts pc
    ON c.stay_id = pc.stay_id
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM cohort_with_counts
)

SELECT
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(hospital_los) AS avg_hospital_los,
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_percentage
FROM quintiles
GROUP BY quintile
ORDER BY quintile;