WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        i.stay_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        i.intime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON a.hadm_id = i.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE 
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
        AND (
            di.long_title LIKE '%upper gastrointestinal bleeding%' 
            OR di.long_title LIKE '%gastrointestinal hemorrhage%'
            OR (di.long_title LIKE '%hemorrhage%' AND (di.long_title LIKE '%upper%' OR di.long_title LIKE '%stomach%' OR di.long_title LIKE '%duodenum%' OR di.long_title LIKE '%esophagus%'))
        )
),
procedures_count AS (
    SELECT 
        c.stay_id,
        COUNT(CASE WHEN di.label LIKE '%endoscopy%' 
                    OR di.label LIKE '%EGD%' 
                    OR di.label LIKE '%diagnostic%' 
                    OR di.label LIKE '%upper gastrointestinal%' 
                    OR di.label LIKE '%gastrointestinal%' 
                THEN pe.itemid END) AS proc_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON c.stay_id = pe.stay_id
        AND pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON pe.itemid = di.itemid
    GROUP BY c.stay_id
),
quintiles AS (
    SELECT 
        pc.stay_id,
        pc.proc_count,
        NTILE(5) OVER (ORDER BY pc.proc_count) AS quintile
    FROM procedures_count pc
)
SELECT 
    q.quintile,
    AVG(q.proc_count) AS avg_procedures,
    AVG(DATE_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los_days,
    SUM(c.hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_percent
FROM quintiles q
JOIN cohort c ON q.stay_id = c.stay_id
GROUP BY q.quintile
ORDER BY q.quintile;