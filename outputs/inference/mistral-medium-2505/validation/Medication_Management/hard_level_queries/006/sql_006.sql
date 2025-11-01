WITH
-- Get male patients aged 37-47
male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 37 AND 47
),

-- Get their admissions with ICU stays
icu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Identify postoperative ICU admissions (within 24 hours of surgery)
postop_icu AS (
  SELECT
    ia.*,
    p.chartdate AS surgery_date
  FROM
    icu_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  ON
    ia.subject_id = p.subject_id AND ia.hadm_id = p.hadm_id
  WHERE
    -- Filter for surgical procedures (ICD-9 procedure codes typically start with numbers)
    REGEXP_CONTAINS(p.icd_code, r'^[0-9]')
    AND TIMESTAMP_DIFF(ia.icu_intime, p.chartdate, HOUR) BETWEEN 0 AND 24
),

-- Calculate medication complexity in first 72 hours of ICU
med_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    -- Count unique medications
    COUNT(DISTINCT
      CASE
        WHEN ph.medication IS NOT NULL THEN ph.medication
        WHEN pr.drug IS NOT NULL THEN pr.drug
        ELSE NULL
      END
    ) AS unique_med_count,
    -- Count total administrations
    COUNT(*) AS total_med_admin,
    -- Count unique routes
    COUNT(DISTINCT
      CASE
        WHEN ph.route IS NOT NULL THEN ph.route
        WHEN pr.route IS NOT NULL THEN pr.route
        WHEN e.route IS NOT NULL THEN e.route
        ELSE NULL
      END
    ) AS unique_route_count,
    -- Count unique dosage forms
    COUNT(DISTINCT pr.form_rx) AS unique_form_count
  FROM
    postop_icu p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  ON
    p.subject_id = ph.subject_id AND p.hadm_id = ph.hadm_id
    AND ph.starttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 72 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 72 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    p.subject_id = e.subject_id AND p.hadm_id = e.hadm_id
    AND e.charttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 72 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  ON
    p.subject_id = ie.subject_id AND p.hadm_id = ie.hadm_id AND p.stay_id = ie.stay_id
    AND ie.starttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id
),

-- Create composite medication complexity score
complexity_score AS (
  SELECT
    *,
    -- Simple weighted score (can be adjusted based on clinical relevance)
    (unique_med_count * 0.4 + total_med_admin * 0.3 + unique_route_count * 0.2 + unique_form_count * 0.1) AS complexity_score
  FROM
    med_complexity
),

-- Assign quintiles based on complexity score
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS complexity_quintile
  FROM
    complexity_score
),

-- Calculate outcomes by quintile
outcomes_by_quintile AS (
  SELECT
    q.complexity_quintile,
    COUNT(*) AS patient_count,
    AVG(q.icu_los_hours) AS avg_icu_los,
    AVG(q.hospital_los_hours) AS avg_hospital_los,
    SUM(q.hospital_expire_flag) / COUNT(*) AS mortality_rate,
    -- Calculate 30-day readmission rate
    SUM(CASE WHEN a2.subject_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS readmission_rate
  FROM
    quintiles q
  JOIN
    postop_icu p ON q.subject_id = p.subject_id AND q.hadm_id = p.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
  ON
    a2.subject_id = q.subject_id
    AND a2.admittime > p.dischtime
    AND TIMESTAMP_DIFF(a2.admittime, p.dischtime, DAY) <= 30
  GROUP BY
    q.complexity_quintile
)

-- Final results
SELECT
  complexity_quintile,
  patient_count,
  avg_icu_los,
  avg_hospital_los,
  mortality_rate,
  readmission_rate
FROM
  outcomes_by_quintile
ORDER BY
  complexity_quintile;