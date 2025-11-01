WITH first_icu_stays AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        ROW_NUMBER() OVER (PARTITION BY ie.subject_id, ie.hadm_id ORDER BY ie.intime) AS stay_seq
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),
ich_cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.hospital_expire_flag,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN first_icu_stays icu
        ON a.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id AND p.subject_id = diag.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 60 AND 70
        AND diag.icd_version = 10
        AND REGEXP_CONTAINS(diag.icd_code, r'^I6[0-2]')
        AND icu.stay_seq = 1
),
procedure_burden AS (
    SELECT 
        ich.subject_id,
        ich.hadm_id,
        ich.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM ich_cohort ich
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON ich.stay_id = pe.stay_id
        AND pe.starttime >= ich.intime
        AND pe.starttime < DATETIME_ADD(ich.intime, INTERVAL 72 HOUR)
    GROUP BY ich.subject_id, ich.hadm_id, ich.stay_id
),
cohort_stats AS (
    SELECT
        APPROX_QUANTILE(num_procedures, 0.75) AS p75_procedure_burden,
        AVG(ich.los) AS mean_icu_los_cohort,
        AVG(CAST(ich.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_cohort
    FROM ich_cohort ich
    LEFT JOIN procedure_burden pb
        ON ich.stay_id = pb.stay_id
),
general_icu_pop AS (
    SELECT 
        AVG(icu.los) AS mean_icu_los_general,
        AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_general
    FROM first_icu_stays icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON icu.hadm_id = a.hadm_id
    WHERE icu.stay_seq = 1
)
SELECT 
    cs.p75_procedure_burden,
    cs.mean_icu_los_cohort,
    cs.hospital_mortality_cohort,
    gp.mean_icu_los_general,
    gp.hospital_mortality_general
FROM cohort_stats cs, general_icu_pop gp;