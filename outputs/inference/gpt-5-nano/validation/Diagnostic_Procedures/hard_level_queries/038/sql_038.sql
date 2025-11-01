WITH ranked_first_icustays AS (
  -- Identify the first ICU stay per subject
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) AS i
  WHERE i.rn = 1
),

ich_cohort AS (
  -- Filter to male patients aged 60-70 with intracranial hemorrhage in the first ICU stay
  SELECT fi.subject_id, fi.hadm_id, fi.stay_id, fi.intime, fi.los
  FROM ranked_first_icustays fi
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = fi.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
    ON dicd.hadm_id = fi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON ddi.icd_code = dicd.icd_code
   AND ddi.icd_version = dicd.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%intracranial hemorrhage%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
),

burden_72h AS (
  -- Compute procedure burden in the first 72 hours for each subject's first ICU stay
  SELECT ic.subject_id,
         ic.stay_id,
         ic.intime,
         (
           SELECT COUNT(*) 
           FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
           WHERE pe.stay_id = ic.stay_id
             AND pe.starttime >= ic.intime
             AND pe.starttime < TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
         ) AS burden_72h_num
  FROM ich_cohort ic
),

p75_burden AS (
  -- 75th percentile of the 72h burden across the subset
  SELECT
    APPROX_QUANTILES(burden_72h_num, 100)[OFFSET(75)] AS p75_burden_72h
  FROM burden_72h
),

subset_los AS (
  -- Mean ICU LOS for the subset (in days)
  SELECT AVG(los) / 24 AS subset_mean_los_days
  FROM ich_cohort
),

subset_mortality AS (
  -- Hospital mortality for the subset
  SELECT AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS subset_hosp_mortality
  FROM ich_cohort ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = ic.hadm_id
),

general_metrics AS (
  -- General ICU population metrics
  SELECT AVG(i.los) / 24 AS general_mean_los_days,
         AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS general_hosp_mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = i.hadm_id
)

SELECT
  p75_burden.p75_burden_72h AS p75_burden_72h,
  subset_los.subset_mean_los_days,
  subset_mortality.subset_hosp_mortality,
  general_metrics.general_mean_los_days,
  general_metrics.general_hosp_mortality
FROM p75_burden
CROSS JOIN subset_los
CROSS JOIN subset_mortality
CROSS JOIN general_metrics;