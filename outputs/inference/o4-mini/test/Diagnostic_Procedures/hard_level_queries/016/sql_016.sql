WITH first_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

pneumonia_patients AS (
  SELECT DISTINCT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    fi.intime,
    fi.los
  FROM
    first_icu fi
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON fi.subject_id = di.subject_id
      AND fi.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%pneumonia%'
),

eligible_patients AS (
  SELECT
    pp.subject_id,
    pp.hadm_id,
    pp.stay_id,
    pp.intime,
    pp.los
  FROM
    pneumonia_patients pp
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON pp.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),

proc_counts AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    ep.stay_id,
    ep.los,
    a.hospital_expire_flag,
    COUNT(pe.starttime) AS proc_count
  FROM
    eligible_patients ep
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON ep.subject_id = pe.subject_id
      AND ep.hadm_id = pe.hadm_id
      AND ep.stay_id = pe.stay_id
      AND pe.starttime BETWEEN ep.intime
                         AND TIMESTAMP_ADD(ep.intime, INTERVAL 72 HOUR)
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON ep.subject_id = a.subject_id
      AND ep.hadm_id = a.hadm_id
  GROUP BY
    ep.subject_id,
    ep.hadm_id,
    ep.stay_id,
    ep.los,
    a.hospital_expire_flag
),

quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    hospital_expire_flag,
    proc_count,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM
    proc_counts
)

SELECT
  quintile,
  ROUND(AVG(proc_count), 2)                          AS avg_proc_count,
  ROUND(AVG(los), 2)                                 AS avg_icu_los,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;