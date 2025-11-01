WITH first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE i.stay_id IN (
    SELECT stay_id
    FROM (
      SELECT
        subject_id,
        stay_id,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    )
    WHERE rn = 1
  )
),

pneumonia_patients AS (
  SELECT DISTINCT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    f.hospital_expire_flag
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),

eligible_patients AS (
  SELECT
    p.subject_id,
    p.stay_id,
    p.intime,
    p.los,
    p.hospital_expire_flag
  FROM pneumonia_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 88 AND 98
),

procedure_counts AS (
  SELECT
    e.subject_id,
    e.stay_id,
    COUNT(pe.itemid) AS proc_count
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON e.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE di.category = 'Diagnostic'
    AND pe.starttime >= e.intime
    AND pe.starttime <= DATETIME_ADD(e.intime, INTERVAL 72 HOUR)
  GROUP BY e.subject_id, e.stay_id
),

quintiles AS (
  SELECT
    subject_id,
    stay_id,
    proc_count,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM procedure_counts
),

quintile_stats AS (
  SELECT
    q.quintile,
    AVG(q.proc_count) AS avg_procedure_count,
    AVG(e.los) AS avg_icu_los_days,
    AVG(e.hospital_expire_flag) * 100 AS in_hospital_mortality_percent
  FROM quintiles q
  JOIN eligible_patients e
    ON q.stay_id = e.stay_id
  GROUP BY q.quintile
)

SELECT
  quintile,
  avg_procedure_count,
  avg_icu_los_days,
  in_hospital_mortality_percent
FROM quintile_stats
ORDER BY quintile;