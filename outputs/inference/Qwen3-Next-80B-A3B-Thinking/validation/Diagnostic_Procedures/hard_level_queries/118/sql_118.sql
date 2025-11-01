WITH first_icu_stay AS (
    SELECT 
        hadm_id,
        stay_id,
        intime
    FROM (
        SELECT 
            hadm_id,
            stay_id,
            intime,
            ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
        FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) 
    WHERE rn = 1
),
amii_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        i.intime AS first_icu_intime,
        i.stay_id,
        p.anchor_age,
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN first_icu_stay i ON a.hadm_id = i.hadm_id
    WHERE 
        p.gender = 'F'
        AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
        AND d.icd_version = 10
        AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 44 AND 54
),
procedure_count AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        COUNT(pe.itemid) AS procedure_count
    FROM amii_patients a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON a.stay_id = pe.stay_id
        AND pe.starttime BETWEEN a.first_icu_intime AND a.first_icu_intime + INTERVAL 72 HOUR
    GROUP BY a.subject_id, a.hadm_id
),
cohort AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.first_icu_intime,
        COALESCE(pc.procedure_count, 0) AS procedure_count,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM amii_patients a
    LEFT JOIN procedure_count pc 
        ON a.subject_id = pc.subject_id AND a.hadm_id = pc.hadm_id
),
quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY procedure_count) AS quartile
    FROM cohort
)
SELECT 
    quartile,
    COUNT(*) AS n,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;