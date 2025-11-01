WITH eligible_patients AS (
  SELECT 
    subject_id,
    anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 63 AND 73
),
first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
),
icu_stays_with_rr AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    ce.charttime,
    ce.valuenum AS resp_rate,
    ce.valueuom
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.category = 'Vital Signs'
    AND di.label IN ('Respiratory Rate', 'Respiratory Rate (Total)')
    AND di.unitname IN ('breaths/minute', 'BPM', 'breaths/min')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
max_rr_per_icu_stay AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    MAX(resp_rate) AS max_rr_stay
  FROM icu_stays_with_rr
  GROUP BY subject_id, hadm_id, stay_id
),
max_rr_per_admission AS (
  SELECT 
    subject_id,
    hadm_id,
    MAX(max_rr_stay) AS max_rr_admission
  FROM max_rr_per_icu_stay
  GROUP BY subject_id, hadm_id
),
max_rr_per_patient AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    m.max_rr_admission
  FROM first_admissions f
  INNER JOIN max_rr_per_admission m
    ON f.subject_id = m.subject_id
    AND f.hadm_id = m.hadm_id
  WHERE f.rn = 1
)
SELECT 
  STDDEV_POP(max_rr_admission) AS std_dev
FROM max_rr_per_patient
WHERE max_rr_admission IS NOT NULL;