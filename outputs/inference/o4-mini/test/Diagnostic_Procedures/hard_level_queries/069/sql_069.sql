WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(dd.long_title) LIKE '%pulmonary embolism%'
),
first_icu AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    istay.stay_id,
    istay.intime,
    ROW_NUMBER() OVER (PARTITION BY c.subject_id, c.hadm_id ORDER BY istay.intime) AS rn
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` istay
      ON c.subject_id = istay.subject_id
      AND c.hadm_id = istay.hadm_id
)
, first_icu_stay AS (
  -- Keep only the first ICU stay per admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM first_icu
  WHERE rn = 1
),
proc_counts AS (
  -- Count distinct procedures in first 72h of ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    f.intime,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.subject_id = pe.subject_id
    AND f.hadm_id = pe.hadm_id
    AND f.stay_id = pe.stay_id
    AND pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.intime
),
analysis_prep AS (
  -- Combine cohort, proc counts, compute LOS
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS hospital_los_days,
    c.hospital_expire_flag
  FROM cohort c
  JOIN first_icu_stay f
    ON c.subject_id = f.subject_id
    AND c.hadm_id = f.hadm_id
  LEFT JOIN proc_counts pc
    ON f.subject_id = pc.subject_id
    AND f.hadm_id = pc.hadm_id
),
quintiled AS (
  -- Assign quintiles based on procedure count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS proc_quintile
  FROM analysis_prep
)
-- Final aggregation by quintile
SELECT
  proc_quintile,
  ROUND(AVG(procedure_count), 2) AS avg_procedure_count,
  ROUND(AVG(hospital_los_days), 2)   AS avg_hospital_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent
FROM quintiled
GROUP BY proc_quintile
ORDER BY proc_quintile;