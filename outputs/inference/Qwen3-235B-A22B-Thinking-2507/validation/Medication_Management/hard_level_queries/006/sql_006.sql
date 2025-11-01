WITH 
-- Filter patients by gender and age
patients_filtered AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 37 AND 47
),

-- Get hospital admissions for these patients
admissions_filtered AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN patients_filtered p
        ON a.subject_id = p.subject_id
),

-- Get first ICU stay per admission
icu_first AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS icu_seq
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN admissions_filtered a
        ON i.hadm_id = a.hadm_id
),

-- Identify postoperative stays (any procedure during admission)
postop_icu AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM icu_first i
    INNER JOIN admissions_filtered a
        ON i.hadm_id = a.hadm_id
    WHERE i.icu_seq = 1
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
          WHERE p.hadm_id = i.hadm_id
      )
),

-- Calculate medication complexity (distinct medications in first 72 hours)
med_complexity AS (
    SELECT 
        p.stay_id,
        COUNT(DISTINCT ie.itemid) AS complexity_score
    FROM postop_icu p
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON p.stay_id = ie.stay_id
        AND ie.starttime >= p.intime
        AND ie.starttime < TIMESTAMP_ADD(p.intime, INTERVAL 72 HOUR)
    GROUP BY p.stay_id
),

-- Assign quintiles based on complexity score
quintiles AS (
    SELECT 
        p.*,
        COALESCE(m.complexity_score, 0) AS complexity_score,
        NTILE(5) OVER (ORDER BY COALESCE(m.complexity_score, 0)) AS quintile
    FROM postop_icu p
    LEFT JOIN med_complexity m
        ON p.stay_id = m.stay_id
),

-- Calculate 30-day readmission flag
readmissions AS (
    SELECT
        a1.hadm_id,
        CASE 
            WHEN MIN(a2.admittime) IS NOT NULL 
            AND TIMESTAMP_DIFF(MIN(a2.admittime), a1.dischtime, HOUR) <= 720
            THEN 1 
            ELSE 0 
        END AS readmitted_30d
    FROM admissions_filtered a1
    LEFT JOIN admissions_filtered a2
        ON a1.subject_id = a2.subject_id
        AND a2.admittime > a1.dischtime
    GROUP BY a1.hadm_id, a1.dischtime
)

-- Aggregate outcomes by quintile
SELECT 
    q.quintile,
    COUNT(*) AS patient_count,
    AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, SECOND) / (60 * 60 * 24)) AS avg_los_days,
    AVG(q.hospital_expire_flag) AS mortality_rate,
    AVG(r.readmitted_30d) AS readmission_rate
FROM quintiles q
LEFT JOIN readmissions r
    ON q.hadm_id = r.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;