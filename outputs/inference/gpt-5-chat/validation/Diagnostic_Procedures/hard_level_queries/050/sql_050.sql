WITH ami_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.subject_id = di.subject_id
   AND adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE UPPER(dd.long_title) LIKE '%ACUTE MYOCARDIAL INFARCTION%'
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    p.gender,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id = adm.hadm_id
  JOIN ami_admissions ami
    ON icu.subject_id = ami.subject_id
   AND icu.hadm_id = ami.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
proc_counts AS (
  SELECT
    c.*,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
   AND pe.starttime >= c.intime
   AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.anchor_age, c.gender, c.intime, c.los, c.hospital_expire_flag
),
with_quartiles AS (
  SELECT
    pc.*,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_quartile
  FROM proc_counts pc
)
SELECT
  proc_quartile,
  AVG(proc_count) AS mean_proc_count,
  AVG(los) AS mean_icu_los_days,
  100 * AVG(hospital_expire_flag) AS hospital_mortality_percent
FROM with_quartiles
GROUP BY proc_quartile
ORDER BY proc_quartile;