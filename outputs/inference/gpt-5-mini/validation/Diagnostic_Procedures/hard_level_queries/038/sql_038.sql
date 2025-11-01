WITH first_icustays AS (
  -- pick the first ICU stay per patient
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
  WHERE rn = 1
),

proc_counts AS (
  -- count procedureevents per first ICU stay within first 72 hours
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    COALESCE(COUNT(pe.starttime), 0) AS proc_count_72h
  FROM first_icustays f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = f.stay_id
    AND pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id, f.intime, f.outtime, f.los
),

ich_admissions AS (
  -- admissions that contain intracranial hemorrhage diagnoses (ICD-9 and ICD-10 heuristics + title search)
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    (
      dd.long_title IS NOT NULL
      AND (
        (LOWER(dd.long_title) LIKE '%intracranial%' AND LOWER(dd.long_title) LIKE '%hemorrh%')
        OR LOWER(dd.long_title) LIKE '%intracerebral%'
      )
    )
    OR d.icd_code IN ('431', '432')                     -- ICD-9 codes for intracerebral/other intracranial hemorrhage
    OR STARTS_WITH(d.icd_code, 'I61')                   -- ICD-10 intracerebral hemorrhage
    OR STARTS_WITH(d.icd_code, 'I62')                   -- ICD-10 other nontraumatic intracranial hemorrhage
  )
),

cohort_base AS (
  -- join proc_counts to patients and admissions to get age, gender and hospital mortality
  SELECT
    pc.*,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag
  FROM proc_counts pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pc.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pc.hadm_id = adm.hadm_id
)

-- final aggregation: target cohort (male, age 60-70, ICH) vs general first-ICU population
SELECT
  cohort_label,
  n_stays,
  p75_proc_count,
  mean_icu_los_days,
  hospital_mortality
FROM (
  -- target cohort: male patients age 60-70 with intracranial hemorrhage (first ICU stay)
  SELECT
    'ICH males age 60-70 (first ICU stay)' AS cohort_label,
    COUNT(*) AS n_stays,
    -- 75th percentile of procedures in first 72h (approximate)
    (APPROX_QUANTILES(proc_count_72h, 4))[OFFSET(3)] AS p75_proc_count,
    AVG(los) AS mean_icu_los_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS hospital_mortality
  FROM cohort_base cb
  WHERE
    cb.gender = 'M'
    AND cb.anchor_age BETWEEN 60 AND 70
    AND cb.hadm_id IN (SELECT hadm_id FROM ich_admissions)

  UNION ALL

  -- general ICU population: all first ICU stays
  SELECT
    'General first-ICU-stay population' AS cohort_label,
    COUNT(*) AS n_stays,
    (APPROX_QUANTILES(proc_count_72h, 4))[OFFSET(3)] AS p75_proc_count,
    AVG(los) AS mean_icu_los_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS hospital_mortality
  FROM cohort_base cb
)
ORDER BY cohort_label;