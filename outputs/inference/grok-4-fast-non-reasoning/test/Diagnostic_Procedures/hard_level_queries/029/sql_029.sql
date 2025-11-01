WITH cohort AS (
  -- Base cohort: male patients 68-78 with ICU stay and vasopressors within 72h
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE ie.subject_id = icu.subject_id
        AND ie.stay_id = icu.stay_id
        AND ie.itemid IN (220615, 221906, 30047, 30044)  -- Norepi, Vasopressin, Dopamine, Epi
        AND ie.rate > 0
        AND ie.starttime >= icu.intime
        AND ie.starttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
      GROUP BY ie.subject_id, ie.stay_id  -- Ensure distinct for EXISTS
    )
),

base_cohort AS (
  -- Select first ICU stay per patient for index analysis
  SELECT 
    c.subject_id,
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM cohort c
  INNER JOIN (
    SELECT subject_id, stay_id, hadm_id, intime, outtime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu ON c.subject_id = icu.subject_id AND icu.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = icu.hadm_id
  WHERE a.dischtime IS NOT NULL  -- Exclude ongoing admissions
),

diagnostic_load AS (
  -- 72h diagnostic load: labs + imaging per patient (repeats included)
  SELECT 
    bc.subject_id,
    bc.stay_id,
    bc.intime,
    COALESCE(SUM(lab_count), 0) + COALESCE(SUM(imaging_count), 0) AS total_diagnostic_load
  FROM base_cohort bc
  LEFT JOIN (
    -- Labs within 72h, filtered by category
    SELECT 
      le.subject_id,
      le.stay_id,  -- Link via stay_id if available, else hadm_id
      COUNT(*) AS lab_count  -- Count all events (repeats included)
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON le.subject_id = icu.subject_id AND le.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON dli.itemid = le.itemid
    WHERE le.valuenum IS NOT NULL
      AND dli.category IN ('Chemistry', 'Blood Gas', 'Hematology', 'Urine', 'Microbiology')
      AND le.charttime >= icu.intime
      AND le.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
    GROUP BY le.subject_id, icu.stay_id
  ) labs ON labs.subject_id = bc.subject_id AND labs.stay_id = bc.stay_id
  LEFT JOIN (
    -- Imaging procedures within 72h (using procedureevents for timed events)
    SELECT 
      pe.subject_id,
      pe.stay_id,
      COUNT(*) AS imaging_count  -- Count all events (repeats included)
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = pe.itemid
    WHERE pe.itemid IN (220739, 220452, 226170, 228069, 228073)  -- CXR, ABG-related, CT head, etc.
      AND di.category = 'Procedures'
      AND pe.starttime >= pe.stay_id's intime  -- Assumes join to icustays for intime, but filter per stay
    GROUP BY pe.subject_id, pe.stay_id
  ) imaging ON imaging.subject_id = bc.subject_id AND imaging.stay_id = bc.stay_id
  GROUP BY bc.subject_id, bc.stay_id, bc.intime
),

outcomes AS (
  -- Outcomes per patient (entire ICU stay for procedures, hospital-level for others)
  SELECT 
    bc.subject_id,
    -- Procedure count: non-imaging procedures over entire ICU stay
    COUNT(CASE WHEN pe.itemid NOT IN (220739, 220452, 226170, 228069, 228073) 
               AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.d_items` di WHERE di.itemid = pe.itemid AND di.category = 'Procedures')
               THEN 1 END) AS procedure_count,
    DATE_DIFF(bc.dischtime, bc.admittime, DAY) AS hospital_los,
    bc.hospital_expire_flag AS in_hospital_mortality,
    -- 30-day readmission
    CASE 
      WHEN bc.hospital_expire_flag = 1 THEN 0.0
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
        WHERE a2.subject_id = bc.subject_id 
          AND a2.hadm_id != bc.hadm_id 
          AND a2.admittime >= bc.dischtime 
          AND a2.admittime < TIMESTAMP_ADD(bc.dischtime, INTERVAL 30 DAY)
      ) THEN 1.0 
      ELSE 0.0 
    END AS readmission_30d_flag
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON pe.subject_id = bc.subject_id 
    AND pe.stay_id = bc.stay_id
    AND pe.starttime >= bc.intime 
    AND pe.starttime <= bc.outtime
  GROUP BY bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag
)

-- Combine and stratify by quartiles
SELECT 
  quartile,
  ROUND(AVG(total_diagnostic_load), 2) AS avg_diagnostic_load,
  ROUND(AVG(procedure_count), 2) AS avg_procedure_count,
  ROUND(AVG(hospital_los), 2) AS avg_hospital_los,
  ROUND(AVG(in_hospital_mortality), 4) AS in_hospital_mortality_rate,
  ROUND(AVG(readmission_30d_flag), 4) AS readmission_30d_rate
FROM (
  SELECT 
    dl.subject_id,
    dl.total_diagnostic_load,
    o.procedure_count,
    o.hospital_los,
    o.in_hospital_mortality,
    o.readmission_30d_flag,
    NTILE(4) OVER (ORDER BY dl.total_diagnostic_load) AS quartile
  FROM diagnostic_load dl
  INNER JOIN outcomes o ON dl.subject_id = o.subject_id
)
GROUP BY quartile
ORDER BY quartile;