WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.admission_type,
        a.dischtime,
        a.hospital_expire_flag,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los AS icu_los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
        AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
    -- Take the first ICU stay per admission
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) = 1
),

medications AS (
    SELECT 
        c.stay_id,
        COUNT(DISTINCT e.medication) AS med_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
        ON c.subject_id = e.subject_id
        AND c.hadm_id = e.hadm_id
        AND e.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.stay_id
),

quintiles AS (
    SELECT
        stay_id,
        med_count,
        NTILE(5) OVER (ORDER BY med_count) AS quintile
    FROM medications
),

readmissions AS (
    SELECT
        a1.subject_id,
        a1.hadm_id,
        a1.dischtime,
        COUNT(DISTINCT a2.hadm_id) > 0 AS readmit_30d
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a1
        ON c.hadm_id = a1.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
        ON a1.subject_id = a2.subject_id
        AND a2.admittime > a1.dischtime
        AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
    GROUP BY a1.subject_id, a1.hadm_id, a1.dischtime
)

SELECT
    q.quintile,
    COUNT(*) AS n_patients,
    AVG(q.med_count) AS avg_med_count,
    MIN(q.med_count) AS min_med_count,
    MAX(q.med_count) AS max_med_count,
    AVG(c.icu_los) AS avg_icu_los,
    AVG(CAST(c.hospital_expire_flag AS INT)) AS mortality_rate,
    AVG(CAST(r.readmit_30d AS INT)) AS readmit_rate
FROM quintiles q
INNER JOIN cohort c
    ON q.stay_id = c.stay_id
INNER JOIN readmissions r
    ON c.hadm_id = r.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;