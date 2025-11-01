WITH first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),
male_age_filtered AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los
  FROM first_icu icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = icu.subject_id
  WHERE rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
pneumonia_patients AS (
  SELECT DISTINCT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.intime,
    m.los
  FROM male_age_filtered m
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON m.subject_id = d.subject_id
    AND m.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    -- ICD-10 J13-J18 or ICD-9 486
    (d.icd_version = 10 AND (d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%' OR 
                             d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR 
                             d.icd_code LIKE 'J17%' OR d.icd_code LIKE 'J18%'))
    OR
    (d.icd_version = 9 AND d.icd_code = '486')
),
proc_counts AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.los,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM pneumonia_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.subject_id = pe.subject_id
    AND p.hadm_id = pe.hadm_id
    AND p.stay_id = pe.stay_id
    AND pe.starttime >= p.intime
    AND pe.starttime < DATETIME_ADD(p.intime, INTERVAL 48 HOUR)
  GROUP BY p.subject_id, p.hadm_id, p.stay_id, p.los
),
quintiled AS (
  SELECT
    pc.*,
    a.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY pc.proc_count) AS quintile
  FROM proc_counts pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pc.hadm_id = a.hadm_id
)
SELECT
  quintile,
  AVG(proc_count) AS mean_proc_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM quintiled
GROUP BY quintile
ORDER BY quintile;