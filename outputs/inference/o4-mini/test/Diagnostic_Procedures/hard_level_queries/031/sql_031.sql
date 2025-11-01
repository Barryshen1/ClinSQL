WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.intime AS icu_intime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    USING (subject_id, hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
       AND d.icd_version = dicd.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%hyperosmolar%'
    )
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.hosp_los,
    COUNT(pe.starttime) AS proc_count
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = c.subject_id
   AND pe.hadm_id = c.hadm_id
   AND pe.stay_id = c.stay_id
   AND pe.starttime >= c.icu_intime
   AND pe.starttime < TIMESTAMP_ADD(c.icu_intime, INTERVAL 48 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.hosp_los
),
readmit30 AS (
  SELECT
    pc.*,
    CASE
      WHEN TIMESTAMP_DIFF(
             (SELECT MIN(a2.admittime)
              FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
              WHERE a2.subject_id = pc.subject_id
                AND a2.admittime > pc.dischtime),
             pc.dischtime,
             DAY
           ) <= 30
      THEN 1
      ELSE 0
    END AS readmit30_flag
  FROM
    proc_counts pc
),
with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS proc_quintile
  FROM
    readmit30
)
SELECT
  proc_quintile AS quintile,
  COUNT(stay_id)                              AS n_icustays,
  ROUND(AVG(proc_count), 2)                   AS mean_procs,
  MIN(proc_count)                             AS min_procs,
  MAX(proc_count)                             AS max_procs,
  ROUND(100.0 * AVG(hospital_expire_flag), 1) AS pct_hosp_mortality,
  ROUND(AVG(hosp_los), 2)                     AS mean_hosp_los_days,
  ROUND(100.0 * AVG(readmit30_flag), 1)       AS pct_30d_readmit
FROM
  with_quintile
GROUP BY
  proc_quintile
ORDER BY
  proc_quintile;