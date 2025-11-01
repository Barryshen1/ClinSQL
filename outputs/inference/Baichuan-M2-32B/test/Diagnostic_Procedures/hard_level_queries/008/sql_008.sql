WITH eligible_admissions AS (
    SELECT 
        a.hadm_id, 
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate LOS in days
        DATEDIFF(DAY, a.admittime, a.dischtime) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 48 AND 58
        AND (
            d.icd_code LIKE 'K25%' OR 
            d.icd_code LIKE 'K26%' OR 
            d.icd_code LIKE 'K27%' OR 
            d.icd_code LIKE 'K31%' OR 
            d.icd_code = 'K92.2'
        )
),
icu_stays AS (
    SELECT 
        i.stay_id,
        i.hadm_id,
        i.subject_id,
        i.intime,
        i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN eligible_admissions e 
        ON i.hadm_id = e.hadm_id AND i.subject_id = e.subject_id
),
first_24h_procedures AS (
    SELECT 
        i.stay_id,
        i.hadm_id,
        i.subject_id,
        i.intime,
        -- Count distinct procedures using linkorderid
        COUNT(DISTINCT pe.linkorderid) AS procedure_count
    FROM icu_stays i
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON i.stay_id = pe.stay_id 
        AND pe.starttime BETWEEN i.intime AND i.intime + INTERVAL 24 HOUR
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON pe.itemid = di.itemid 
        AND di.category IN ('Imaging', 'Procedure', 'Diagnostic', 'Endoscopy')
    GROUP BY i.stay_id, i.hadm_id, i.subject_id, i.intime
),
quintiles AS (
    SELECT 
        f.*,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM first_24h_procedures f
)
SELECT 
    q.quintile,
    AVG(q.procedure_count) AS avg_procedures,
    AVG(e.los_days) AS avg_los_days,
    AVG(e.hospital_expire_flag) * 100 AS mortality_percent
FROM quintiles q
INNER JOIN eligible_admissions e 
    ON q.hadm_id = e.hadm_id AND q.subject_id = e.subject_id
GROUP BY q.quintile
ORDER BY q.quintile;