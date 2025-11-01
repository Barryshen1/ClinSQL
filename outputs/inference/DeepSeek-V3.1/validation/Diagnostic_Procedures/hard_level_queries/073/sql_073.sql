WITH cohort AS (
    -- Get first ICU stay for male patients aged 90-100 with hepatic failure
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ie.hadm_id = diag.hadm_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 90 AND 100
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'K72%') OR
            (diag.icd_version = 9 AND diag.icd_code BETWEEN '570' AND '573')
        )
        -- Ensure first ICU stay
        AND ie.intime = (
            SELECT MIN(ie2.intime)
            FROM `physionet-data.mimiciv_3_1_icu.icustays` ie2
            WHERE ie2.subject_id = ie.subject_id
        )
),
procedures AS (
    -- Count distinct procedures per patient in first 72 hours
    SELECT 
        c.subject_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON c.stay_id = pe.stay_id
        AND pe.starttime >= c.intime
        AND pe.starttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.subject_id
),
quartiles AS (
    -- Assign quartile based on procedure count
    SELECT 
        p.subject_id,
        p.num_procedures,
        NTILE(4) OVER (ORDER BY p.num_procedures) AS quartile
    FROM procedures p
)
-- Aggregate by quartile
SELECT 
    q.quartile,
    COUNT(*) AS num_patients,
    MIN(q.num_procedures) AS min_procedures,
    MAX(q.num_procedures) AS max_procedures,
    ROUND(AVG(q.num_procedures), 2) AS mean_procedures,
    ROUND(AVG(c.los), 2) AS mean_los_days,
    ROUND(100.0 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM quartiles q
INNER JOIN cohort c
    ON q.subject_id = c.subject_id
GROUP BY q.quartile
ORDER BY q.quartile;