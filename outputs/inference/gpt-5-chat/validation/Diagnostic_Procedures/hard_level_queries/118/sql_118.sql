WITH ami_hadm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE ( (di.icd_version = 9 AND di.icd_code LIKE '410%')
       OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')) )
),
first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
)
, cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    fi.stay_id,
    fi.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hosp_los
  FROM ami_hadm a
  JOIN first_icu fi
    ON a.subject_id = fi.subject_id
   AND a.hadm_id = fi.hadm_id
   AND fi.rn = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON a.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
)
, proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(pe.itemid) AS proc_count,
    c.hosp_los,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
   AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.hosp_los, c.hospital_expire_flag
)
, quartiles AS (
  SELECT
    pc.*,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_quartile
  FROM proc_counts pc
)
SELECT
  proc_quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(proc_count),2) AS mean_proc_count,
  ROUND(AVG(hosp_los),2) AS mean_hosp_los_days,
  ROUND(100 * AVG(hospital_expire_flag),2) AS mortality_percent
FROM quartiles
GROUP BY proc_quartile
ORDER BY proc_quartile;