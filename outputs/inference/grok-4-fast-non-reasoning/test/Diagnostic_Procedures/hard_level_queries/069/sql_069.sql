WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Get first ICU stay using subquery
    first_icu.stay_id AS first_stay_id,
    first_icu.intime AS first_intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
    AND d.hadm_id = a.hadm_id
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I26%') OR
      (d.icd_version = 9 AND (d.icd_code LIKE '415.1%' OR d.icd_code = '415.11' OR d.icd_code = '415.19'))
    )
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON p.subject_id = ic.subject_id
    AND a.hadm_id = ic.hadm_id
  INNER JOIN (
    SELECT subject_id, hadm_id, stay_id, intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ic_sub
    WHERE (ic_sub.subject_id, ic_sub.hadm_id, ic_sub.intime) IN (
      SELECT subject_id, hadm_id, MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      GROUP BY subject_id, hadm_id
    )
  ) first_icu
    ON p.subject_id = first_icu.subject_id
    AND a.hadm_id = first_icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.first_stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.subject_id = pe.subject_id
    AND c.hadm_id = pe.hadm_id
    AND c.first_stay_id = pe.stay_id
    AND pe.starttime BETWEEN c.first_intime AND DATE_ADD(c.first_intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.first_stay_id
),
all_procs AS (
  SELECT
    c.subject_id,
    COALESCE(pc.proc_count, 0) AS proc_count,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS hospital_los
  FROM cohort c
  LEFT JOIN proc_counts pc
    ON c.subject_id = pc.subject_id
)
SELECT
  NTILE(5) OVER (ORDER BY proc_count) AS quintile,
  ROUND(AVG(proc_count), 2) AS avg_procedure_count,
  ROUND(AVG(hospital_los), 2) AS avg_hospital_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_percent
FROM all_procs
GROUP BY quintile
ORDER BY quintile;