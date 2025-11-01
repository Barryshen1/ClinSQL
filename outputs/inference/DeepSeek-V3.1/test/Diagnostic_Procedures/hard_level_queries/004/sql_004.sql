WITH
cohort_stays AS (
    SELECT
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.intime,
        ie.outtime,
        ie.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ie.hadm_id = diag.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I61%') OR
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I62%') OR
            (diag.icd_version = 9 AND diag.icd_code BETWEEN '430' AND '432')
        )
),
proc_burden AS (
    SELECT
        cs.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM cohort_stays cs
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON cs.stay_id = pe.stay_id
        AND pe.starttime >= cs.intime
        AND pe.starttime < DATETIME_ADD(cs.intime, INTERVAL 72 HOUR)
    GROUP BY cs.stay_id
),
cohort_summary AS (
    SELECT
        'Cohort' AS group_name,
        APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS procedure_burden_p25,
        APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS procedure_burden_p50,
        APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS procedure_burden_p90,
        APPROX_QUANTILES(cs.los, 100)[OFFSET(50)] AS median_icu_los,
        AVG(CAST(adm.hospital_expire_flag AS INT)) AS mortality_rate
    FROM cohort_stays cs
    INNER JOIN proc_burden pb ON cs.stay_id = pb.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON cs.hadm_id = adm.hadm_id
    GROUP BY group_name
),
general_icu_proc_burden AS (
    SELECT
        ie.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON ie.stay_id = pe.stay_id
        AND pe.starttime >= ie.intime
        AND pe.starttime < DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
    GROUP BY ie.stay_id
),
general_icu_summary AS (
    SELECT
        'General ICU' AS group_name,
        APPROX_QUANTILES(gp.num_procedures, 100)[OFFSET(25)] AS procedure_burden_p25,
        APPROX_QUANTILES(gp.num_procedures, 100)[OFFSET(50)] AS procedure_burden_p50,
        APPROX_QUANTILES(gp.num_procedures, 100)[OFFSET(90)] AS procedure_burden_p90,
        APPROX_QUANTILES(ie.los, 100)[OFFSET(50)] AS median_icu_los,
        AVG(CAST(adm.hospital_expire_flag AS INT)) AS mortality_rate
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    LEFT JOIN general_icu_proc_burden gp
        ON ie.stay_id = gp.stay_id
    GROUP BY group_name
)
SELECT * FROM cohort_summary
UNION ALL
SELECT * FROM general_icu_summary;