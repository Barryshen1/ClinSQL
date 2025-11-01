WITH eligible_icu_stays AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        adm.admittime,
        adm.dischtime,
        icu.intime AS icu_intime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 68 AND 78
),

-- CTE 2: Identify stay_ids that received vasopressors within 72 hours of ICU intime.
-- Common vasopressor itemids based on MIMIC-IV documentation/clinical knowledge.
vasopressor_administrations AS (
    SELECT DISTINCT
        eis.stay_id
    FROM
        eligible_icu_stays eis
    JOIN
        `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON eis.stay_id = ie.stay_id
    WHERE
        ie.itemid IN (
            221906, -- Norepinephrine
            221289, -- Epinephrine
            221662, -- Dopamine
            222315, -- Vasopressin
            221986  -- Phenylephrine
        )
        AND ie.starttime BETWEEN eis.icu_intime AND DATETIME_ADD(eis.icu_intime, INTERVAL 72 HOUR)
),

-- CTE 3: Calculate 72-hour diagnostic load from lab events for each eligible ICU stay.
-- 'Repeats included' means every relevant labevent_id is counted.
lab_load_72hr AS (
    SELECT
        eis.stay_id,
        COUNT(le.labevent_id) AS lab_count_72hr
    FROM
        eligible_icu_stays eis
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON eis.subject_id = le.subject_id AND eis.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN eis.icu_intime AND DATETIME_ADD(eis.icu_intime, INTERVAL 72 HOUR)
    GROUP BY
        eis.stay_id
),

-- CTE 4: Calculate 72-hour diagnostic load from procedures (as a proxy for imaging/diagnostic procedures).
-- 'Repeats included' means every relevant procedures_icd entry is counted.
proc_load_72hr AS (
    SELECT
        eis.stay_id,
        COUNT(pi.seq_num) AS proc_count_72hr
    FROM
        eligible_icu_stays eis
    JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON eis.hadm_id = pi.hadm_id
    WHERE
        -- Convert chartdate to DATETIME for accurate comparison with icu_intime (DATETIME)
        DATETIME(pi.chartdate) BETWEEN eis.icu_intime AND DATETIME_ADD(eis.icu_intime, INTERVAL 72 HOUR)
    GROUP BY
        eis.stay_id
),

-- CTE 5: Combine diagnostic loads for patients meeting all initial criteria (age, gender, vasopressors)
patient_diagnostic_load_base AS (
SELECT
    eis.subject_id,
    eis.hadm_id,
    eis.stay_id,
    eis.admittime,
    eis.dischtime,
    eis.hospital_expire_flag,
    COALESCE(ll.lab_count_72hr, 0) + COALESCE(pl.proc_count_72hr, 0) AS diagnostic_load_72hr
FROM
    eligible_icu_stays eis
JOIN
    vasopressor_administrations vas
    ON eis.stay_id = vas.stay_id
LEFT JOIN
    lab_load_72hr ll
    ON eis.stay_id = ll.stay_id
LEFT JOIN
    proc_load_72hr pl
    ON eis.stay_id = pl.stay_id
), -- REMOVED THE TRAILING COMMA HERE

-- CTE 6: Calculate total procedure count for the entire admission.
total_admission_procedures AS (
    SELECT
        hadm_id,
        COUNT(seq_num) AS total_procedure_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY
        hadm_id
),

-- CTE 7: Prepare admissions data to find the next admission for 30-day readmission flag.
admissions_with_next_admit AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        -- Get the admittime of the next hospital admission for the same patient
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime_for_readmit
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- CTE 8: Calculate 30-day readmission flag for each admission.
readmission_flags AS (
    SELECT
        hadm_id,
        CASE
            WHEN next_admittime_for_readmit IS NOT NULL
            AND DATETIME_DIFF(next_admittime_for_readmit, dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmission_30d_flag
    FROM
        admissions_with_next_admit
),

-- CTE 9: Combine all patient/admission-level metrics and assign diagnostic load quartiles.
patient_data_with_quartiles AS (
    SELECT
        pdl.subject_id,
        pdl.hadm_id,
        pdl.stay_id,
        pdl.diagnostic_load_72hr,
        NTILE(4) OVER (ORDER BY pdl.diagnostic_load_72hr) AS diagnostic_load_quartile,
        DATETIME_DIFF(pdl.dischtime, pdl.admittime, HOUR) / 24.0 AS hospital_los_days,
        pdl.hospital_expire_flag,
        COALESCE(tap.total_procedure_count, 0) AS total_procedure_count_admission,
        COALESCE(rf.readmission_30d_flag, 0) AS readmission_30d_flag
    FROM
        patient_diagnostic_load_base pdl
    LEFT JOIN
        total_admission_procedures tap
        ON pdl.hadm_id = tap.hadm_id
    LEFT JOIN
        readmission_flags rf
        ON pdl.hadm_id = rf.hadm_id
)

-- Final SELECT: Aggregate metrics by diagnostic load quartile.
SELECT
    diagnostic_load_quartile,
    MIN(diagnostic_load_72hr) AS min_diagnostic_load_in_quartile,
    MAX(diagnostic_load_72hr) AS max_diagnostic_load_in_quartile,
    COUNT(DISTINCT stay_id) AS num_icu_stays, -- Number of distinct ICU stays in the quartile
    ROUND(AVG(total_procedure_count_admission), 2) AS avg_total_admission_procedure_count,
    ROUND(AVG(hospital_los_days), 2) AS avg_hospital_los_days,
    ROUND(AVG(hospital_expire_flag), 4) AS in_hospital_mortality_rate, -- Average of 0s and 1s gives the rate
    ROUND(AVG(readmission_30d_flag), 4) AS readmission_30d_rate -- Average of 0s and 1s gives the rate
FROM
    patient_data_with_quartiles
GROUP BY
    diagnostic_load_quartile
ORDER BY
    diagnostic_load_quartile;