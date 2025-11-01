WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    adm.hadm_id,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.subject_id = di.subject_id AND adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND LOWER(dd.long_title) LIKE '%sepsis%'
),
first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
)
, proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    fi.stay_id,
    fi.intime,
    fi.los,
    c.hospital_expire_flag,
    COUNT(DISTINCT pi.icd_code) AS proc_count
  FROM cohort c
  JOIN first_icu fi
    ON c.subject_id = fi.subject_id AND c.hadm_id = fi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON c.subject_id = pi.subject_id AND c.hadm_id = pi.hadm_id
       AND pi.chartdate BETWEEN DATE(fi.intime) AND DATE(fi.intime + INTERVAL 72 HOUR)
  WHERE fi.rn = 1
  GROUP BY c.subject_id, c.hadm_id, fi.stay_id, fi.intime, fi.los, c.hospital_expire_flag
)
, quartiled AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    hospital_expire_flag,
    proc_count,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_quartile
  FROM proc_counts
)
SELECT
  proc_quartile,
  AVG(proc_count) AS mean_proc_count,
  AVG(los) AS mean_icu_los_days,
  100 * AVG(hospital_expire_flag) AS mortality_percent
FROM quartiled
GROUP BY proc_quartile
ORDER BY proc_quartile;