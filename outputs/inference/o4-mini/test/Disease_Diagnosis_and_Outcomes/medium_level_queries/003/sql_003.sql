WITH stroke_admissions AS (
  -- 1. identify male patients age 44-54 with single stroke type
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN MIN(CASE WHEN LOWER(d.long_title) LIKE '%ischemic stroke%' THEN 1 ELSE 0 END) = 1
           AND MIN(CASE WHEN LOWER(d.long_title) LIKE '%hemorrhagic%' THEN 1 ELSE 0 END) = 0
        THEN 'Ischemic'
      WHEN MIN(CASE WHEN LOWER(d.long_title) LIKE '%hemorrhagic%' THEN 1 ELSE 0 END) = 1
           AND MIN(CASE WHEN LOWER(d.long_title) LIKE '%ischemic stroke%' THEN 1 ELSE 0 END) = 0
        THEN 'Hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.subject_id = dx.subject_id
     AND a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON dx.icd_code = d.icd_code
     AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
  GROUP BY
    a.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  HAVING
    stroke_type IS NOT NULL
),

comorbid_counts AS (
  -- 2. count distinct diagnosis codes per admission for comorbidity proxy
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS n_comorbid
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    hadm_id IN (SELECT hadm_id FROM stroke_admissions)
  GROUP BY hadm_id
),

comorbidity_strata AS (
  SELECT
    hadm_id,
    CASE
      WHEN n_comorbid <= 1 THEN 'Low'
      WHEN n_comorbid <= 4 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_level
  FROM comorbid_counts
),

icu_events AS (
  -- 3. for each admission, detect mech vent, vasopressors, RRT in ICU stays
  SELECT
    sa.hadm_id,
    MAX(CASE WHEN pe.itemid IN (720, 721) THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN ie.ordercategoryname IN ('NOREPINEPHRINE','EPINEPHRINE','VASOPRESSIN') THEN 1 ELSE 0 END) AS vasopressor,
    MAX(CASE WHEN pe.itemid IN (227309) THEN 1 ELSE 0 END) AS rrt
  FROM
    stroke_admissions sa
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON sa.subject_id = icu.subject_id
     AND sa.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON icu.subject_id = pe.subject_id
     AND icu.hadm_id = pe.hadm_id
     AND icu.stay_id = pe.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
      ON icu.subject_id = ie.subject_id
     AND icu.hadm_id = ie.hadm_id
     AND icu.stay_id = ie.stay_id
  GROUP BY sa.hadm_id
)

SELECT
  sa.stroke_type,
  CASE
    WHEN sa.los <= 5 THEN '≤5'
    ELSE '>5'
  END AS los_strata,
  cs.comorbidity_level,
  COUNT(*) AS N_admissions,
  ROUND(100.0 * SUM(sa.hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  (APPROX_QUANTILES(sa.los, 2))[OFFSET(1)] AS los_median,
  ROUND(100.0 * SUM(ie.mech_vent) / COUNT(*), 1) AS mechvent_pct,
  ROUND(100.0 * SUM(ie.vasopressor) / COUNT(*), 1) AS vasopressor_pct,
  ROUND(100.0 * SUM(ie.rrt) / COUNT(*), 1) AS rrt_pct
FROM
  stroke_admissions sa
  JOIN comorbidity_strata cs
    ON sa.hadm_id = cs.hadm_id
  JOIN icu_events ie
    ON sa.hadm_id = ie.hadm_id
GROUP BY
  sa.stroke_type,
  los_strata,
  cs.comorbidity_level
ORDER BY
  sa.stroke_type,
  los_strata,
  cs.comorbidity_level;