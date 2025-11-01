WITH
-- Get female patients aged 87-97
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 87 AND 97
),

-- Get admissions for these patients with ICH diagnosis
ich_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    a.discharge_location,
    a.insurance,
    a.admission_type,
    a.admission_location,
    a.marital_status,
    a.race,
    a.language,
    a.edregtime,
    a.edouttime,
    d.icd_code,
    d.icd_version,
    di.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN
    female_patients p ON a.subject_id = p.subject_id
  WHERE
    -- ICD-9 codes for ICH: 430-432
    (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432')
    OR
    -- ICD-10 codes for ICH: I60-I62
    (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I62')
),

-- Get all prescriptions within first 48 hours of admission
early_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.route,
    p.starttime,
    p.stoptime,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    ich_admissions a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    p.starttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
),

-- Calculate medication complexity score (unique drugs + unique routes)
medication_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_drugs,
    COUNT(DISTINCT route) AS unique_routes,
    COUNT(DISTINCT drug) + COUNT(DISTINCT route) AS complexity_score
  FROM
    early_prescriptions
  GROUP BY
    subject_id, hadm_id
),

-- Calculate quartile boundaries
quartile_boundaries AS (
  SELECT
    PERCENTILE_CONT(mc.complexity_score, 0.25) OVER() AS q1,
    PERCENTILE_CONT(mc.complexity_score, 0.5) OVER() AS q2,
    PERCENTILE_CONT(mc.complexity_score, 0.75) OVER() AS q3
  FROM
    medication_complexity mc
  LIMIT 1
),

-- Assign quartiles based on complexity score
quartiles AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.complexity_score,
    CASE
      WHEN mc.complexity_score <= qb.q1 THEN 1
      WHEN mc.complexity_score <= qb.q2 THEN 2
      WHEN mc.complexity_score <= qb.q3 THEN 3
      ELSE 4
    END AS quartile,
    qb.q1 AS min_score_q1,
    qb.q2 AS min_score_q2,
    qb.q3 AS min_score_q3,
    (SELECT MAX(complexity_score) FROM medication_complexity) AS max_score
  FROM
    medication_complexity mc
  CROSS JOIN
    quartile_boundaries qb
),

-- Calculate 30-day readmissions
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS original_hadm_id,
    a2.hadm_id AS readmission_hadm_id,
    a2.admittime AS readmission_time,
    DATE_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmission
  FROM
    ich_admissions a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND DATE_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
    AND a2.hadm_id != a1.hadm_id
)

-- Final result with all required metrics
SELECT
  q.quartile,
  COUNT(DISTINCT q.hadm_id) AS admissions,
  CASE
    WHEN q.quartile = 1 THEN 0
    WHEN q.quartile = 2 THEN q.min_score_q1 + 1
    WHEN q.quartile = 3 THEN q.min_score_q2 + 1
    WHEN q.quartile = 4 THEN q.min_score_q3 + 1
  END AS min_score,
  CASE
    WHEN q.quartile = 1 THEN q.min_score_q1
    WHEN q.quartile = 2 THEN q.min_score_q2
    WHEN q.quartile = 3 THEN q.min_score_q3
    WHEN q.quartile = 4 THEN q.max_score
  END AS max_score,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24) AS avg_los_days,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) * 100 AS mortality_percentage,
  SUM(CASE WHEN r.readmission_hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) * 100 AS readmission_percentage
FROM
  quartiles q
JOIN
  ich_admissions a ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
LEFT JOIN
  readmissions r ON q.subject_id = r.subject_id AND q.hadm_id = r.original_hadm_id
GROUP BY
  q.quartile, q.min_score_q1, q.min_score_q2, q.min_score_q3, q.max_score
ORDER BY
  q.quartile;