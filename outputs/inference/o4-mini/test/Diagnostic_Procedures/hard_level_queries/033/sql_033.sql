WITH pneumonia_adms AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN pneumonia_adms pa
      ON icu.subject_id = pa.subject_id
      AND icu.hadm_id = pa.hadm_id
  WHERE
    icu.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu2
      WHERE icu2.subject_id = icu.subject_id
        AND icu2.hadm_id = icu.hadm_id
    )
),
proc_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.los,
    pa.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM
    first_icu f
    JOIN pneumonia_adms pa
      ON f.subject_id = pa.subject_id
      AND f.hadm_id = pa.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON f.subject_id = pe.subject_id
      AND f.hadm_id = pe.hadm_id
      AND f.stay_id = pe.stay_id
      AND pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.los,
    pa.hospital_expire_flag
),
ranked AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM
    proc_counts
)
SELECT
  quintile,
  ROUND(AVG(proc_count), 2)           AS mean_proc_count,
  ROUND(AVG(los), 2)                  AS mean_icu_los_days,
  ROUND(AVG(hospital_expire_flag), 4) AS hospital_mortality_rate
FROM
  ranked
GROUP BY
  quintile
ORDER BY
  quintile;