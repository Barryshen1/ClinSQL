WITH asthma_adms AS (
  -- Step 1: Male patients 77–87 with an asthma exacerbation admission
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version= dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(dd.long_title) LIKE '%asthma exacerbation%'
  GROUP BY
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),

first_icu AS (
  -- Step 2: First ICU stay per admission
  SELECT
    ia.subject_id,
    ia.hadm_id,
    icu.stay_id,
    icu.intime     AS icu_intime,
    ia.admittime,
    ia.dischtime,
    ia.hospital_expire_flag,
    ia.los_days,
    ROW_NUMBER() OVER (
      PARTITION BY icu.subject_id, icu.hadm_id
      ORDER BY icu.intime
    ) AS rn
  FROM
    asthma_adms ia
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ia.subject_id = icu.subject_id
      AND ia.hadm_id    = icu.hadm_id
),

icu_proc_counts AS (
  -- Step 3: Count procedures in first 72h of ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.icu_intime,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    f.los_days,
    COUNT(pe.starttime) AS proc_count
  FROM
    first_icu f
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON f.subject_id = pe.subject_id
      AND f.hadm_id    = pe.hadm_id
      AND f.stay_id    = pe.stay_id
      AND pe.starttime BETWEEN f.icu_intime
                          AND TIMESTAMP_ADD(f.icu_intime, INTERVAL 72 HOUR)
  WHERE
    f.rn = 1
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.icu_intime,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    f.los_days
),

quartiled AS (
  -- Step 4: Assign quartiles by procedure count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_quartile
  FROM
    icu_proc_counts
)

-- Step 5: Aggregate metrics by quartile
SELECT
  proc_quartile,
  COUNT(*)                             AS n_patients,
  ROUND(AVG(proc_count), 2)           AS mean_proc_count,
  ROUND(AVG(los_days), 2)             AS mean_hospital_los_days,
  ROUND(AVG(hospital_expire_flag), 3) AS hospital_mortality_rate
FROM
  quartiled
GROUP BY
  proc_quartile
ORDER BY
  proc_quartile;