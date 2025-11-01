WITH first_icu AS (
  -- first ICU stay per patient
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

ards_hadm AS (
  -- admissions (hadm_id) that include an ARDS diagnosis (tries to be robust)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE
    -- explicit common codes
    (d.icd_version = 10 AND d.icd_code = 'J80')
    OR (d.icd_version = 9 AND SAFE_CAST(REGEXP_REPLACE(d.icd_code, r'[^0-9]', '') AS STRING) LIKE '51882%')
    -- or descriptive match in the diagnosis text
    OR (LOWER(COALESCE(dic.long_title, '')) LIKE '%acute respiratory distress%')
    OR (LOWER(COALESCE(dic.long_title, '')) LIKE '%ards%')
),

proc_evt_within_72h AS (
  -- ICU procedureevents within 72 hours of ICU intime
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    CONCAT('proc_evt_', CAST(pe.itemid AS STRING), '_', COALESCE(CAST(pe.value AS STRING), '')) AS proc_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN first_icu fi
    ON pe.stay_id = fi.stay_id
  WHERE
    pe.starttime BETWEEN fi.intime AND TIMESTAMP_ADD(fi.intime, INTERVAL 72 HOUR)
),

proc_icd_within_72h AS (
  -- HOSP procedures_icd within (date) 72 hours of ICU intime; chartdate is a DATE
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    CONCAT('icd_', p.icd_code) AS proc_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN first_icu fi
    ON p.hadm_id = fi.hadm_id AND p.subject_id = fi.subject_id
  WHERE
    p.chartdate BETWEEN DATE(fi.intime) AND DATE(TIMESTAMP_ADD(fi.intime, INTERVAL 72 HOUR))
),

all_procs AS (
  -- union distinct procedure identifiers (source prefixed) within 72 hours
  SELECT * FROM proc_evt_within_72h
  UNION DISTINCT
  SELECT * FROM proc_icd_within_72h
),

patient_proc_counts AS (
  -- for each first ICU stay, count distinct procedures in first 72 hours (0 if none)
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    COALESCE(COUNT(DISTINCT ap.proc_id), 0) AS proc_count
  FROM first_icu fi
  LEFT JOIN all_procs ap
    ON fi.subject_id = ap.subject_id
    AND fi.hadm_id = ap.hadm_id
    AND fi.stay_id = ap.stay_id
  GROUP BY fi.subject_id, fi.hadm_id, fi.stay_id
),

patient_info AS (
  -- enrich with patient demographics, admissions LOS, and ARDS flag
  SELECT
    pc.subject_id,
    pat.gender,
    pat.anchor_age,
    pc.proc_count,
    adm.hospital_expire_flag,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, MINUTE), 1440.0) AS los_days,
    CASE WHEN ah.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ards_flag
  FROM patient_proc_counts pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pc.hadm_id = adm.hadm_id AND pc.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pc.subject_id = pat.subject_id
  LEFT JOIN ards_hadm ah
    ON pc.hadm_id = ah.hadm_id AND pc.subject_id = ah.subject_id
)

-- Final cohort statistics: target (female age 37-47 with ARDS) and all ICU patients
SELECT
  cohort,
  n,
  min_proc_count,
  p75_proc_count,
  p90_proc_count,
  ROUND(mean_los_days, 3) AS mean_los_days,
  ROUND(mortality_rate, 4) AS mortality_rate  -- fraction (e.g., 0.1234)
FROM (
  -- Target cohort: female, age 37-47 inclusive, with ARDS on that hadm
  SELECT
    'female_age_37_47_with_ards' AS cohort,
    COUNT(*) AS n,
    MIN(proc_count) AS min_proc_count,
    APPROX_QUANTILES(proc_count, 100)[SAFE_OFFSET(75)] AS p75_proc_count,
    APPROX_QUANTILES(proc_count, 100)[SAFE_OFFSET(90)] AS p90_proc_count,
    AVG(los_days) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM patient_info
  WHERE gender = 'F'
    AND anchor_age BETWEEN 37 AND 47
    AND ards_flag = 1

  UNION ALL

  -- All first ICU stays (no additional filters)
  SELECT
    'all_first_icu_stays' AS cohort,
    COUNT(*) AS n,
    MIN(proc_count) AS min_proc_count,
    APPROX_QUANTILES(proc_count, 100)[SAFE_OFFSET(75)] AS p75_proc_count,
    APPROX_QUANTILES(proc_count, 100)[SAFE_OFFSET(90)] AS p90_proc_count,
    AVG(los_days) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM patient_info
)
ORDER BY cohort;