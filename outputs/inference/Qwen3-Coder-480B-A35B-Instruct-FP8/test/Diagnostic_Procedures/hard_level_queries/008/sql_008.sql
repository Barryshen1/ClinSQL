WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND dd.icd_code IN ('K922', 'K250', 'K252', 'K254', 'K256', 'K260', 'K262', 'K264', 'K266', 'K270', 'K272', 'K274', 'K276', 'K280', 'K282', 'K284', 'K286')
),

procedures_first24 AS (
  SELECT
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE
    pe.starttime >= c.intime
    AND pe.starttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND di.category = 'Diagnostic'
  GROUP BY
    c.stay_id
),

quintiles AS (
  SELECT
    p.stay_id,
    p.proc_count,
    c.hospital_los,
    c.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY p.proc_count) AS quintile
  FROM
    procedures_first24 p
  JOIN
    cohort c
    ON p.stay_id = c.stay_id
)

SELECT
  quintile,
  AVG(proc_count) AS avg_procedures,
  AVG(hospital_los) AS avg_hospital_los,
  AVG(hospital_expire_flag) * 100 AS in_hosp_mortality_percent
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;