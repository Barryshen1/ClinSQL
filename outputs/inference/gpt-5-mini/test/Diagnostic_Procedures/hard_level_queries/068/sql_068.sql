WITH asthma_admissions AS (
  -- Admissions with principal diagnosis mentioning "asthma"
  SELECT
    dx.subject_id,
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON dx.icd_code = d.icd_code
      AND dx.icd_version = d.icd_version
  WHERE
    dx.seq_num = 1
    AND LOWER(d.long_title) LIKE '%asthma%'
  GROUP BY
    dx.subject_id, dx.hadm_id
),

cohort_stays AS (
  -- ICU stays for male patients age 77-87 with an asthma admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
      AND icu.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN asthma_admissions a
      ON icu.subject_id = a.subject_id
      AND icu.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),

proc_counts AS (
  -- Count procedures in the first 72 hours after ICU intime for each stay
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.intime,
    cs.admittime,
    cs.dischtime,
    cs.hospital_expire_flag,
    cs.anchor_age,
    COUNT(pe.starttime) AS proc_count
  FROM
    cohort_stays cs
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON pe.stay_id = cs.stay_id
      AND pe.starttime IS NOT NULL
      AND pe.starttime >= cs.intime
      AND pe.starttime < TIMESTAMP_ADD(cs.intime, INTERVAL 72 HOUR)
  GROUP BY
    cs.subject_id, cs.hadm_id, cs.stay_id, cs.intime, cs.admittime, cs.dischtime, cs.hospital_expire_flag, cs.anchor_age
),

ranked AS (
  -- Assign quartiles based on proc_count distribution
  SELECT
    pc.*,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_quartile
  FROM
    proc_counts pc
)

-- Final aggregation by quartile
SELECT
  proc_quartile AS quartile,
  COUNT(*) AS n_stays,
  ROUND(AVG(proc_count), 2) AS mean_proc_count,
  -- mean hospital LOS in days with fractional days
  ROUND(AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400.0)), 2) AS mean_hospital_los_days,
  -- hospital mortality as percent
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS hospital_mortality_percent
FROM
  ranked
GROUP BY
  proc_quartile
ORDER BY
  proc_quartile;