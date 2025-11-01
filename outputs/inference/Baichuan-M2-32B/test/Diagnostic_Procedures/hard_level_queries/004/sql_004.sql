WITH base_icu AS (
    SELECT 
        i.stay_id,
        i.subject_id,
        i.hadm_id,
        i.intime,
        i.outtime,
        p.gender,
        p.anchor_year,
        p.anchor_age,
        a.admittime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    WHERE 
        p.gender = 'F' 
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 50 AND 60
),
ich_diagnoses AS (
    SELECT 
        d.subject_id,
        d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
        d.icd_version = 10 
        AND dd.long_title LIKE '%intracranial hemorrhage%'
        AND d.seq_num IS NOT NULL
),
ich_icu_stays AS (
    SELECT 
        b.*
    FROM base_icu b
    INNER JOIN ich_diagnoses i 
        ON b.subject_id = i.subject_id AND b.hadm_id = i.hadm_id
),
general_icu_stays AS (
    SELECT 
        b.*
    FROM base_icu b
    LEFT JOIN ich_diagnoses i 
        ON b.subject_id = i.subject_id AND b.hadm_id = i.hadm_id
    WHERE i.subject_id IS NULL
),
ich_procedures AS (
    SELECT 
        s.stay_id,
        COUNT(p.stay_id) AS procedure_count
    FROM ich_icu_stays s
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p 
        ON s.stay_id = p.stay_id
        AND p.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
    GROUP BY s.stay_id
),
ich_percentiles AS (
    SELECT 
        PERCENTILE_CONT(procedure_count, 0.25) OVER() AS p25,
        PERCENTILE_CONT(procedure_count, 0.5) OVER() AS p50,
        PERCENTILE_CONT(procedure_count, 0.9) OVER() AS p90
    FROM ich_procedures
    LIMIT 1
),
ich_metrics AS (
    SELECT 
        AVG(TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) / 24.0) AS avg_los_days,
        AVG(s.hospital_expire_flag) AS mortality_rate
    FROM ich_icu_stays s
),
general_metrics AS (
    SELECT 
        AVG(TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) / 24.0) AS avg_los_days,
        AVG(s.hospital_expire_flag) AS mortality_rate
    FROM general_icu_stays s
),
ich_summary AS (
    SELECT 
        'ICH Cohort' AS cohort,
        p25 AS procedure_25th_percentile,
        p50 AS procedure_50th_percentile,
        p90 AS procedure_90th_percentile,
        NULL AS avg_los_days,
        NULL AS mortality_rate
    FROM ich_percentiles
    UNION ALL
    SELECT 
        'ICH Cohort' AS cohort,
        NULL,
        NULL,
        NULL,
        m.avg_los_days,
        m.mortality_rate
    FROM ich_metrics m
),
general_summary AS (
    SELECT 
        'General ICU' AS cohort,
        NULL AS procedure_25th_percentile,
        NULL AS procedure_50th_percentile,
        NULL AS procedure_90th_percentile,
        m.avg_los_days,
        m.mortality_rate
    FROM general_metrics m
)
SELECT * FROM ich_summary
UNION ALL
SELECT * FROM general_summary
ORDER BY cohort, procedure_25th_percentile DESC NULLS LAST;