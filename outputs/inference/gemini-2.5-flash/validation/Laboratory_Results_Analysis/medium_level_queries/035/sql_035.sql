SELECT
    COUNT(DISTINCT cohort.subject_id) AS num_unique_patients_in_cohort,
    COUNT(DISTINCT cohort.hadm_id) AS num_unique_admissions_in_cohort,
    AVG(DATETIME_DIFF(cohort.dischtime, cohort.admittime, HOUR) / 24.0) AS average_length_of_stay_days,
    AVG(cohort.hospital_expire_flag) AS in_hospital_mortality_rate
FROM
    ( -- CTE: Admissions meeting demographic and ACS diagnosis criteria
        SELECT
            ad.subject_id,
            ad.hadm_id,
            ad.admittime,
            ad.dischtime,
            ad.hospital_expire_flag
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
            ON ad.subject_id = pa.subject_id
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
            ON ad.subject_id = dicd.subject_id AND ad.hadm_id = dicd.hadm_id
        WHERE
            pa.gender = 'M'
            AND pa.anchor_age BETWEEN 73 AND 83
            AND dicd.seq_num = 1 -- Primary diagnosis
            AND dicd.icd_version = 10 -- Using ICD-10 for MIMIC-IV
            AND (
                dicd.icd_code LIKE 'I21%' OR -- Acute myocardial infarction (STEMI, NSTEMI)
                dicd.icd_code LIKE 'I22%' OR -- Subsequent myocardial infarction
                dicd.icd_code LIKE 'I24%'    -- Other acute ischemic heart diseases
            )
    ) AS cohort
INNER JOIN
    ( -- CTE: Initial elevated Troponin T for each admission
        SELECT
            le.subject_id,
            le.hadm_id,
            le.valuenum AS troponin_t_value,
            ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
        WHERE
            le.itemid = 50993 -- Troponin T (lookup in d_labitems)
            AND le.valuenum IS NOT NULL
            AND le.valuenum > 0.04 -- Clinical threshold for elevated Troponin T (e.g., > 0.04 ng/mL)
    ) AS initial_troponin_t_filtered
    ON cohort.subject_id = initial_troponin_t_filtered.subject_id
    AND cohort.hadm_id = initial_troponin_t_filtered.hadm_id
WHERE
    initial_troponin_t_filtered.rn = 1 -- Ensure we only pick the very first Troponin T measurement
;