WITH first_icu AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.los AS icu_los,
    ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),

pneumonia_adm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE UPPER(dd.long_title) LIKE '%PNEUMONIA%'
),

cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    fi.stay_id,
    fi.intime,
    fi.icu_los,
    a.hospital_expire_flag
  FROM first_icu fi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fi.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fi.hadm_id = a.hadm_id
  INNER JOIN pneumonia_adm pa
    ON fi.subject_id = pa.subject_id AND fi.hadm_id = pa.hadm_id
  WHERE fi.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),

proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.icu_los,
    c.hospital_expire_flag,
    COUNT(pi.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON c.hadm_id = pi.hadm_id
   AND pi.chartdate BETWEEN DATE(c.intime)
                        AND DATE(c.intime + INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.icu_los, c.hospital_expire_flag
),

quintiles AS (
  SELECT
    pc.*,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts pc
)

SELECT
  quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(proc_count), 2) AS avg_proc_count,
  ROUND(AVG(icu_los), 2) AS avg_icu_los_days,
  ROUND(100.0 * AVG(hospital_expire_flag), 1) AS mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;