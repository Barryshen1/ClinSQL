WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.intime,
        icu.outtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 66 AND 76
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'E11.00%') OR
            (diag.icd_version = 9 AND diag.icd_code LIKE '250.2%')
        )
),

procedures_48h AS (
    -- Procedures from procedures_icd (using chartdate, so we use date range)
    SELECT 
        coh.stay_id,
        proc.chartdate,
        COUNT(*) AS cnt
    FROM cohort coh
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON coh.hadm_id = proc.hadm_id
    WHERE proc.chartdate BETWEEN DATE(coh.intime) AND DATE(TIMESTAMP_ADD(coh.intime, INTERVAL 48 HOUR))
    GROUP BY coh.stay_id, proc.chartdate

    UNION ALL

    -- Procedures from procedureevents (using charttime)
    SELECT 
        coh.stay_id,
        DATE(proc.starttime) AS chartdate,
        COUNT(*) AS cnt
    FROM cohort coh
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
        ON coh.stay_id = proc.stay_id
    WHERE proc.starttime BETWEEN coh.intime AND TIMESTAMP_ADD(coh.intime, INTERVAL 48 HOUR)
    GROUP BY coh.stay_id, chartdate
),

stay_procedure_count AS (
    SELECT 
        stay_id,
        SUM(cnt) AS procedure_count
    FROM procedures_48h
    GROUP BY stay_id
),

cohort_with_procedures AS (
    SELECT 
        coh.*,
        COALESCE(spc.procedure_count, 0) AS procedure_count
    FROM cohort coh
    LEFT JOIN stay_procedure_count spc
        ON coh.stay_id = spc.stay_id
),

readmission_flag AS (
    SELECT 
        c.*,
        -- Check if there is a next admission within 30 days of discharge
        CASE 
            WHEN LEAD(admittime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime) 
                <= DATE_ADD(c.dischtime, INTERVAL 30 DAY) 
            THEN 1 
            ELSE 0 
        END AS readmit_30d
    FROM cohort_with_procedures c
),

quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM readmission_flag
)

SELECT 
    quintile,
    COUNT(*) AS num_icu_stays,
    AVG(procedure_count) AS mean_procedures,
    MIN(procedure_count) AS min_procedures,
    MAX(procedure_count) AS max_procedures,
    AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent,
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR)) / 24.0 AS mean_hospital_los_days,
    AVG(readmit_30d) * 100 AS readmission_30d_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;