WITH cohort AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

vasopressor_patients AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ie.starttime >= c.intime
    AND (di.label LIKE '%vasopressor%'
        OR di.label LIKE '%norepinephrine%'
        OR di.label LIKE '%epinephrine%'
        OR di.label LIKE '%vasopressin%'
        OR di.label LIKE '%phenylephrine%'
        OR di.label LIKE '%dopamine%')
),

diagnostic_load AS (
  SELECT 
    vp.subject_id,
    vp.hadm_id,
    vp.stay_id,
    COUNT(le.labevent_id) AS lab_count,
    COUNT(poe.poe_id) AS imaging_count,
    COUNT(le.labevent_id) + COUNT(poe.poe_id) AS total_diagnostic_load
  FROM vasopressor_patients vp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON vp.hadm_id = le.hadm_id
    AND vp.subject_id = le.subject_id
    AND le.charttime >= vp.intime
    AND le.charttime <= DATETIME_ADD(vp.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.poe` poe
    ON vp.hadm_id = poe.hadm_id
    AND vp.subject_id = poe.subject_id
    AND poe.ordertime >= vp.intime
    AND poe.ordertime <= DATETIME_ADD(vp.intime, INTERVAL 72 HOUR)
    AND poe.order_type = 'Radiology'
  GROUP BY vp.subject_id, vp.hadm_id, vp.stay_id
),

quartiles AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    total_diagnostic_load,
    NTILE(4) OVER (ORDER BY total_diagnostic_load) AS quartile
  FROM diagnostic_load
),

procedures AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),

readmissions AS (
  SELECT 
    a1.subject_id,
    a1.hadm_id,
    CASE WHEN MIN(a2.admittime) IS NOT NULL AND a1.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS readmit_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
  GROUP BY a1.subject_id, a1.hadm_id, a1.hospital_expire_flag
)

SELECT 
  q.quartile,
  COUNT(*) AS n_patients,
  AVG(p.procedure_count) AS avg_procedure_count,
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los_days,
  AVG(a.hospital_expire_flag) AS in_hospital_mortality,
  AVG(r.readmit_30d) AS readmission_30d_rate
FROM quartiles q
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON q.hadm_id = a.hadm_id
LEFT JOIN procedures p
  ON q.hadm_id = p.hadm_id
LEFT JOIN readmissions r
  ON q.hadm_id = r.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;