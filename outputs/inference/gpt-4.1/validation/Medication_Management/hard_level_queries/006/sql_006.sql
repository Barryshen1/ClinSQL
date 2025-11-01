WITH cohort AS (
  -- Select male patients aged 37-47 with postoperative ICU admission
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type LIKE '%SURGICAL%'
),
med_complexity AS (
  -- Count unique medications administered in first 72h of ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT di.label) AS med_complexity
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
      ON c.subject_id = ie.subject_id
      AND c.hadm_id = ie.hadm_id
      AND c.stay_id = ie.stay_id
      AND ie.starttime >= c.icu_intime
      AND ie.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ie.itemid = di.itemid
      AND di.category = 'Medications'
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),
outcomes AS (
  -- Calculate 30-day readmission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    -- 30-day readmission: does another admission start within 30 days after discharge?
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime >= c.dischtime
          AND a2.admittime < DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    cohort c
),
full_data AS (
  -- Combine medication complexity and outcomes
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.stay_id,
    mc.med_complexity,
    o.los,
    o.hospital_expire_flag,
    o.readmit_30d
  FROM
    med_complexity mc
    JOIN outcomes o
      ON mc.subject_id = o.subject_id
      AND mc.hadm_id = o.hadm_id
      AND mc.stay_id = o.stay_id
),
quintiles AS (
  -- Assign quintiles based on medication complexity
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity) AS complexity_quintile
  FROM
    full_data
),
summary AS (
  -- Aggregate outcomes per quintile
  SELECT
    complexity_quintile,
    COUNT(*) AS n_patients,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
    AVG(readmit_30d) AS readmit_30d_rate,
    MIN(med_complexity) AS min_complexity,
    MAX(med_complexity) AS max_complexity
  FROM
    quintiles
  GROUP BY
    complexity_quintile
),
index_patient AS (
  -- Find the index patient's complexity and quintile
  SELECT
    q.subject_id,
    q.hadm_id,
    q.stay_id,
    q.med_complexity,
    q.complexity_quintile,
    s.avg_los,
    s.in_hosp_mortality_rate,
    s.readmit_30d_rate
  FROM
    quintiles q
    JOIN summary s
      ON q.complexity_quintile = s.complexity_quintile
  WHERE
    q.med_complexity IS NOT NULL
    AND q.subject_id IN (
      -- Find a 42-year-old man with a postoperative ICU admission
      SELECT subject_id
      FROM cohort
      WHERE anchor_age = 42
      LIMIT 1
    )
)
-- Final output: summary table and index patient risk
SELECT
  'summary' AS section,
  *
FROM summary
UNION ALL
SELECT
  'index_patient' AS section,
  complexity_quintile,
  NULL AS n_patients,
  med_complexity AS avg_los,
  in_hosp_mortality_rate,
  readmit_30d_rate,
  NULL AS min_complexity,
  NULL AS max_complexity
FROM index_patient
ORDER BY section, complexity_quintile;